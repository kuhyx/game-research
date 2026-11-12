import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/cli.dart';
import 'package:game_research/analysis/job_lock.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

void main() {
  late Fixture fx;
  late FakeSys fake;
  late File errFile;
  late String data;

  Future<int> run(List<String> args) async {
    final sink = errFile.openWrite();
    final code = await analyzeMain(
      args,
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
    return code;
  }

  setUp(() {
    fx = Fixture();
    data = p.join(fx.root.path, 'data');
    errFile = File(p.join(fx.root.path, 'err.txt'))..createSync();
    fake = FakeSys()
      ..onStart = ffmpegStart
      ..onRun = (c) {
        switch (c.exe) {
          case 'ffmpeg':
            return ffmpegFake(c);
          case '/fake/llm':
            return ok(c.args.first == 'opus' ? kAnswer : kCaptionJson);
          case 'faketodo':
            return ok('task-1');
        }
        return ok('git@github.com:kuhyx/cleanup-plate.git\n');
      };
  });

  test('bad arguments print the usage and exit 2', () async {
    for (final args in [
      <String>[],
      ['a', 'b'],
      ['--finish'],
      ['--finish', 'alpha', 'extra'],
      ['--finish', 'alpha', '--force'],
      ['--resume-all', 'x'],
      ['dir', '--bogus'],
    ]) {
      expect(await run(args), 2, reason: '$args');
      expect(errFile.readAsStringSync(), contains('usage:'), reason: '$args');
    }
    expect(fake.calls, isEmpty);
  });

  test('a session dir runs its job', () async {
    expect(await run([fx.session.path]), 0);
    expect(fx.status['state'], 'done');
  });

  test('--force is passed on', () async {
    await run([fx.session.path]);
    fake.calls.clear();
    expect(await run([fx.session.path, '--force']), 0);
    expect(fake.of('ffmpeg'), isNotEmpty);
  });

  test('--finish runs the finish job of the game', () async {
    expect(await run([fx.session.path]), 0);
    fake.onRun = (c) => switch (c.exe) {
      '/fake/llm' => ok(finishAnswer()),
      'git' => ok('git@github.com:kuhyx/cleanup-plate.git\n'),
      _ => ok('t-1'),
    };
    expect(await run(['--finish', 'alpha']), 0);
    final finish = jsonDecode(
      File(p.join(data, 'games', 'alpha', 'finish.json')).readAsStringSync(),
    ) as Map;
    expect(finish['state'], 'done');
  });

  test('--resume-all relaunches what is unfinished', () async {
    fx.out('status.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'state': 'interrupted'}));
    expect(await run(['--resume-all']), 0);
    expect(fx.status['state'], 'done');
  });

  test('after its job the queue drains: the next waiting job runs', () async {
    final queued = Directory(p.join(data, '20261113-100000-alpha'))
      ..createSync();
    File(p.join(queued.path, 'session.json'))
        .writeAsStringSync(jsonEncode(fx.meta));
    File(p.join(queued.path, 'recording.mkv')).writeAsStringSync('v');
    File(p.join(queued.path, 'analysis', 'status.json'))
      ..parent.createSync()
      ..writeAsStringSync(jsonEncode({'state': 'waiting'}));
    expect(await run([fx.session.path]), 0);
    expect(
      jsonDecode(
        File(p.join(queued.path, 'analysis', 'status.json')).readAsStringSync(),
      ),
      containsPair('state', 'done'),
    );
  });

  test('a job queued behind another does not drain', () async {
    final other = JobLock(data, selfPid: pid)..acquire('someone-else');
    expect(await run([fx.session.path]), 4);
    expect(fake.calls, isEmpty);
    other.release();
  });

  test('a queued --force keeps its force through the drain', () async {
    expect(await run([fx.session.path]), 0);
    final other = JobLock(data, selfPid: pid)..acquire('someone-else');
    fake.calls.clear();
    expect(await run([fx.session.path, '--force']), 4);
    expect(fake.calls, isEmpty);
    other.release();
    expect(await run(['--resume-all']), 0);
    expect(fake.of('ffmpeg'), isNotEmpty, reason: 'redone from scratch');
    fake.calls.clear();
    expect(await run(['--resume-all']), 0);
    expect(fake.calls, isEmpty, reason: 'the force is spent');
  });

  test('a job that already runs is exit 3 with no drain', () async {
    final held = JobLock(data, selfPid: pid)
      ..acquire(p.basename(fx.session.path));
    expect(await run([fx.session.path]), 3);
    held.release();
  });
}
