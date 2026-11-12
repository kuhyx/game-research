import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/job.dart';
import 'package:game_research/analysis/resume.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

// kuhy, 2026-11-11: the 23:10 power-off left NUL bytes and a torn last line
// in captions.jsonl; `--resume-all` died on a FormatException and no session
// was resumed. Damaged files read as absent, and one bad job never stops the
// next.
void main() {
  late Fixture fx;
  late FakeSys fake;
  late String data;

  ResumeAll resumer({Future<int> Function(String dir)? runSession}) =>
      ResumeAll(
        testConfig(
          fx.root,
          extra: {
            'GAME_RESEARCH_FAKE_LLM': '/fake/llm',
            'GAME_RESEARCH_TODO_CMD': 'faketodo',
            'GAME_RESEARCH_STILL_S': '2',
          },
        ),
        fake.sys,
        MockClient((_) async => throw StateError('no network in tests')),
        recordingPoll: const Duration(milliseconds: 5),
        runSession: runSession,
      );

  Directory session(String stamp) {
    final d = Directory(p.join(data, '$stamp-alpha'))
      ..createSync(recursive: true);
    File(p.join(d.path, 'session.json'))
        .writeAsStringSync(jsonEncode({...fx.meta, 'duration_s': 40}));
    File(p.join(d.path, 'recording.mkv')).writeAsStringSync('v');
    File(p.join(d.path, 'markers.jsonl')).writeAsStringSync('');
    return d;
  }

  File status(Directory d) => File(p.join(d.path, 'analysis', 'status.json'));

  Map<String, Object?> statusOf(Directory d) =>
      jsonDecode(status(d).readAsStringSync()) as Map<String, Object?>;

  void write(Directory d, String name, String text) =>
      File(p.join(d.path, 'analysis', name))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);

  setUp(() {
    fx = Fixture();
    data = p.join(fx.root.path, 'data');
    Directory(fx.session.path).deleteSync(recursive: true);
    fake = FakeSys()
      ..onStart = ffmpegStart
      ..onRun = (c) {
        switch (c.exe) {
          case 'ffmpeg':
            return ffmpegFake(c);
          case '/fake/llm':
            return c.args.first == 'opus' ? ok(kAnswer) : ok(kCaptionJson);
          case 'faketodo':
            return ok('task-1');
        }
        return bad('no remote', 2);
      };
  });

  test(
    'a captions.jsonl with a NUL-filled torn tail resumes to done',
    () async {
      final d = session('20261111-185105');
      final good = jsonEncode({
        'frame': 'f_0000.png',
        't': 0,
        'usage': {'in': 5, 'out': 2},
      });
      // The power cut: one whole row, then half a row and a run of NULs.
      write(
        d,
        'captions.jsonl',
        '$good\n{"frame":"f_0001.png","t":5,"cap\x00\x00\x00\x00',
      );
      write(
        d,
        'status.json',
        jsonEncode({'stage': 2, 'done': 1, 'total': 4, 'state': 'running'}),
      );
      expect(await resumer().run(), 0);
      expect(statusOf(d)['state'], 'done');
      final raw = File(p.join(d.path, 'analysis', 'captions.jsonl'))
          .readAsStringSync();
      expect(raw, isNot(contains('\x00')));
      for (final line in const LineSplitter().convert(raw)) {
        expect(jsonDecode(line), isA<Map<String, Object?>>());
      }
      expect(raw, contains('f_0001.png'), reason: 'the torn frame is redone');
    },
  );

  test('a corrupt status.json counts as absent and the job reruns', () async {
    final d = session('20261111-185105');
    write(d, 'status.json', '{"stage":2,"do\x00\x00\x00');
    expect(await resumer().run(), 0);
    expect(statusOf(d)['state'], 'done');
  });

  test('a corrupt stage3.json does not stop the usage tally', () {
    final d = session('20261111-185105');
    write(d, 'stage3.json', '\x00\x00{"tok');
    write(
      d,
      'captions.jsonl',
      '${jsonEncode({
        'frame': 'f',
        't': 0,
        'usage': {'in': 7},
      })}\n\x00\x00',
    );
    expect(sessionUsage(d.path).input, 7);
  });

  test('one session that throws is failed and the next still runs', () async {
    final a = session('20261111-185105');
    final b = session('20261111-193823');
    final seen = <String>[];
    final code = await resumer(
      runSession: (dir) async {
        seen.add(p.basename(dir));
        if (dir == a.path) throw StateError('disk on fire');
        return 0;
      },
    ).run();
    expect(seen, [p.basename(a.path), p.basename(b.path)]);
    expect(statusOf(a)['state'], 'failed');
    expect(statusOf(a)['error'], contains('disk on fire'));
    expect(code, isNot(0), reason: 'non-zero only after trying them all');
  });

  test('a crash keeps the stage and tokens the status already had', () async {
    final a = session('20261111-185105');
    write(
      a,
      'status.json',
      jsonEncode({
        'stage': 2,
        'done': 1,
        'total': 4,
        'state': 'waiting',
        'retry_unix': 1.0,
        'tokens': {'in': 9},
      }),
    );
    final code = await resumer(
      runSession: (_) async => throw StateError('boom'),
    ).run();
    expect(code, 1);
    expect(statusOf(a), containsPair('stage', 2));
    expect(statusOf(a), containsPair('state', 'failed'));
    expect((statusOf(a)['tokens']! as Map)['in'], 9);
  });

  test('a failure that cannot be recorded does not stop the loop', () async {
    final a = session('20261111-185105');
    session('20261111-193823');
    // `analysis` is a file: neither a job nor the failed mark can write.
    File(p.join(a.path, 'analysis')).writeAsStringSync('x');
    final seen = <String>[];
    final code = await resumer(
      runSession: (dir) async {
        seen.add(p.basename(dir));
        if (dir == a.path) throw StateError('boom');
        return 0;
      },
    ).run();
    expect(seen, hasLength(2));
    expect(code, 1);
  });

  test('a damaged session.json is skipped, the others still run', () async {
    final a = session('20261111-185105');
    final b = session('20261111-193823');
    File(p.join(a.path, 'session.json')).writeAsStringSync('\x00\x00{"du');
    expect(await resumer().run(), 0);
    expect(statusOf(b)['state'], 'done');
    expect(status(a).existsSync(), isFalse);
  });

  test('a retention failure does not stop the resume', () async {
    final a = session('20261111-185105');
    write(
      a,
      'status.json',
      jsonEncode({'stage': 3, 'done': 1, 'total': 1, 'state': 'done'}),
    );
    final b = session('20261111-193823');
    File(p.join(data, 'games', 'alpha', 'finish.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'state': 'done',
          'finished_unix': 1,
          'sessions': ['20261111-185105'],
        }),
      );
    // A read-only session folder: deleting its recording throws.
    Process.runSync('chmod', ['a-w', a.path]);
    addTearDown(() => Process.runSync('chmod', ['u+w', a.path]));
    expect(await resumer().run(), 0);
    expect(statusOf(b)['state'], 'done');
  });

  test('no .tmp file is left behind by status writes', () async {
    final d = session('20261111-185105');
    expect(await resumer().run(), 0);
    final left = Directory(d.path)
        .listSync(recursive: true)
        .where((e) => e.path.endsWith('.tmp'));
    expect(left, isEmpty);
  });
}
