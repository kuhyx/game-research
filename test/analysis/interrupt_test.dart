import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/cli.dart';
import 'package:game_research/analysis/job.dart';
import 'package:game_research/analysis/job_lock.dart';
import 'package:game_research/analysis/resume.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/core/usage.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

// kuhy, 2026-11-12: the coordinator stopped the resume unit for a deploy; the
// SIGTERMed job left "running" in its status.json, which looked like a job
// that still ran while another process held the lock.

void main() {
  late Fixture fx;
  late FakeSys fake;
  late String data;

  Map<String, Object?> json(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

  Directory session(String stamp, String state) {
    final d = Directory(p.join(data, '$stamp-alpha'))
      ..createSync(recursive: true);
    File(p.join(d.path, 'session.json')).writeAsStringSync(jsonEncode(fx.meta));
    File(p.join(d.path, 'recording.mkv')).writeAsStringSync('v');
    File(p.join(d.path, 'markers.jsonl')).writeAsStringSync('');
    File(p.join(d.path, 'analysis', 'status.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({'stage': 2, 'done': 3, 'total': 9, 'state': state}),
      );
    return d;
  }

  String stateOf(Directory d) =>
      json(p.join(d.path, 'analysis', 'status.json'))['state']! as String;

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

  ResumeAll resumer() => ResumeAll(
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
  );

  for (final (name, signal, code) in [
    ('SIGTERM', ProcessSignal.sigterm, 143),
    ('SIGINT', ProcessSignal.sigint, 130),
  ]) {
    test('$name writes interrupted, frees the lock and exits $code', () async {
      final file = File(p.join(fx.root.path, 'status.json'));
      final status = StatusWriter(file, fake.sys, () => Usage.zero);
      final signals = StreamController<ProcessSignal>();
      final exits = <int>[];
      final inBody = Completer<void>();
      final release = Completer<void>();
      final job = runLocked(
        job: 'job-a',
        config: testConfig(fx.root),
        status: status,
        stops: [signals.stream],
        exitFn: exits.add,
        body: (stage) async {
          stage.value = 2;
          status.write(2, 4, 9, StageState.running);
          inBody.complete();
          await release.future;
        },
      );
      await inBody.future;
      expect(JobLock(data).holder()?.job, 'job-a');
      signals.add(signal);
      await Future<void>.delayed(Duration.zero);
      expect(exits, [code]);
      final s = json(file.path);
      expect(
        [s['state'], s['stage'], s['done'], s['total']],
        ['interrupted', 2, 4, 9],
      );
      expect(JobLock(data).holder(), isNull);
      release.complete();
      await job;
      await signals.close();
    });
  }

  test(
    '--resume-all marks a dead running job even while another runs',
    () async {
      final dead = session('20261111-185105', 'running');
      final owner = JobLock(data, selfPid: pid)..acquire('someone-else');
      expect(await resumer().run(), 0);
      expect(stateOf(dead), 'interrupted');
      expect(fake.calls, isEmpty, reason: 'nothing starts behind a live job');
      owner.release();
    },
  );

  test('a finish behind a dead running session runs it, then itself', () async {
    final dead = session('20261111-185105', 'running');
    File(p.join(data, 'games', 'alpha', 'finish.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'state': 'queued', 'appid': 1}));
    final err = File(p.join(fx.root.path, 'err.txt'))..createSync();
    final sink = err.openWrite();
    final code = await analyzeMain(
      ['--finish', 'alpha'],
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
      err: sink,
    );
    await sink.close();
    expect(code, JobExit.waiting, reason: 'the finish itself queued');
    expect(stateOf(dead), 'done');
    expect(
      json(p.join(data, 'games', 'alpha', 'status.json'))['state'],
      'done',
    );
    expect(JobLock(data).holder(), isNull);
  });
}
