import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/finish.dart';
import 'package:game_research/analysis/job_lock.dart';
import 'package:game_research/analysis/resume.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:game_research/desktop/config.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

// kuhy, 2026-11-12: "research finished" must queue behind the game's own
// session analyses (they feed it) instead of failing or merging half.

void main() {
  late Fixture fx;
  late FakeSys fake;
  late String data;

  Config cfg() => testConfig(
    fx.root,
    extra: {
      'GAME_RESEARCH_FAKE_LLM': '/fake/llm',
      'GAME_RESEARCH_TODO_CMD': 'faketodo',
      'GAME_RESEARCH_STILL_S': '2',
    },
  );

  FinishRunner runner() => FinishRunner(
    'alpha',
    cfg(),
    fake.sys,
    recordingPoll: const Duration(milliseconds: 5),
  );

  Map<String, Object?> json(String name) =>
      jsonDecode(File(p.join(data, 'games', 'alpha', name)).readAsStringSync())
          as Map<String, Object?>;

  /// Session [stamp] of alpha: recorded, with [status] (null: none).
  Directory session(String stamp, {String? status, bool draft = false}) {
    final d = Directory(p.join(data, '$stamp-alpha'))
      ..createSync(recursive: true);
    File(p.join(d.path, 'session.json')).writeAsStringSync(jsonEncode(fx.meta));
    File(p.join(d.path, 'recording.mkv')).writeAsStringSync('v');
    File(p.join(d.path, 'markers.jsonl')).writeAsStringSync('');
    Directory(p.join(d.path, 'analysis')).createSync();
    if (status != null) {
      File(p.join(d.path, 'analysis', 'status.json')).writeAsStringSync(
        jsonEncode({'stage': 2, 'done': 0, 'total': 1, 'state': status}),
      );
    }
    if (draft) {
      final path = draftPath(fx.target.path, 'alpha', stamp);
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(kDraft);
      File(p.join(d.path, 'analysis', 'stage3.json'))
          .writeAsStringSync(jsonEncode({'draft': path, 'todo': 't'}));
    }
    return d;
  }

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
            return c.args.first != 'opus'
                ? ok(kCaptionJson)
                : ok(c.args.last.contains('finish') ? finishAnswer() : kAnswer);
          case 'faketodo':
            return ok('task-1');
        }
        return ok('git@github.com:kuhyx/cleanup-plate.git\n');
      };
  });

  for (final state in ['running', 'waiting', 'interrupted', 'idle']) {
    test('a $state session of the game holds the finish: waiting', () async {
      session('20261111-100000', draft: true, status: 'done');
      session('20261112-100000', status: state);
      expect(await runner().run(), 4);
      expect(json('status.json')['state'], 'waiting');
      expect(json('status.json')['error'], contains('20261112-100000'));
      expect(fake.of('/fake/llm'), isEmpty);
      expect(JobLock(data).holder(), isNull, reason: 'sessions may run');
    });
  }

  test('a session never started (recording, no status) holds it too', () async {
    session('20261111-100000', draft: true, status: 'done');
    session('20261112-100000');
    expect(await runner().run(), 4);
  });

  test('failed, done and still-recording sessions do not hold it', () async {
    session('20261111-100000', draft: true, status: 'done');
    session('20261111-110000', status: 'failed');
    final live = session('20261112-100000');
    File(p.join(live.path, 'session.json'))
        .writeAsStringSync(jsonEncode({...fx.meta}..remove('duration_s')));
    expect(await runner().run(), 0);
    expect(json('finish.json')['state'], 'done');
  });

  test(
    '--resume-all runs a queued finish (no status) behind sessions',
    () async {
      final pending = session('20261112-100000');
      File(p.join(data, 'games', 'alpha', 'finish.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'state': 'queued', 'appid': 1}));
      final resume = ResumeAll(
        cfg(),
        fake.sys,
        MockClient((_) async => throw StateError('no network in tests')),
        recordingPoll: const Duration(milliseconds: 5),
      );
      expect(await resume.run(), 0);
      expect(
        jsonDecode(
          File(p.join(pending.path, 'analysis', 'status.json'))
              .readAsStringSync(),
        ),
        containsPair('state', 'done'),
      );
      expect(json('finish.json'), containsPair('state', 'done'));
      expect(json('finish.json'), containsPair('appid', 1));
      expect(json('finish.json')['sessions'], ['20261112-100000']);
    },
  );
}
