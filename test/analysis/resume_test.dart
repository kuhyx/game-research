import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/finish.dart';
import 'package:game_research/analysis/job_lock.dart';
import 'package:game_research/analysis/resume.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

// kuhy, 2026-11-12: the 23:10 shutdown killed three jobs and their status
// stayed "running" for good. --resume-all picks every unfinished job up.
void main() {
  late Fixture fx;
  late FakeSys fake;
  late String data;
  var opusAnswer = ok(kAnswer);

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

  /// A stopped session folder [stamp] with a recording, like the fixture's.
  Directory session(String stamp, {bool video = true, double? duration = 40}) {
    final d = Directory(p.join(data, '$stamp-alpha'))
      ..createSync(recursive: true);
    File(p.join(d.path, 'session.json')).writeAsStringSync(
      jsonEncode({...fx.meta..remove('duration_s'), 'duration_s': ?duration}),
    );
    if (video) File(p.join(d.path, 'recording.mkv')).writeAsStringSync('v');
    File(p.join(d.path, 'markers.jsonl')).writeAsStringSync('');
    return d;
  }

  void writeStatus(Directory d, String state, {double? retry}) =>
      File(p.join(d.path, 'analysis', 'status.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'stage': 2,
            'done': 1,
            'total': 4,
            'state': state,
            'retry_unix': ?retry,
          }),
        );

  String stateOf(Directory d) =>
      (jsonDecode(
            File(p.join(d.path, 'analysis', 'status.json')).readAsStringSync(),
          ) as Map)['state']
          as String;

  setUp(() {
    fx = Fixture();
    data = p.join(fx.root.path, 'data');
    // The fixture's own session is just one more folder here.
    Directory(fx.session.path).deleteSync(recursive: true);
    opusAnswer = ok(kAnswer);
    fake = FakeSys()
      ..onStart = ffmpegStart
      ..onRun = (c) {
        switch (c.exe) {
          case 'ffmpeg':
            return ffmpegFake(c);
          case '/fake/llm':
            return c.args.first == 'opus' ? opusAnswer : ok(kCaptionJson);
          case 'faketodo':
            return ok('task-1');
        }
        return bad('no remote', 2);
      };
  });

  test(
    'an interrupted job (status running, process dead) runs to done',
    () async {
      final d = session('20261111-185105');
      writeStatus(d, 'running');
      expect(await resumer().run(), 0);
      expect(stateOf(d), 'done');
    },
  );

  test('markInterrupted rewrites only the dead running jobs', () {
    final dead = session('20261111-185105');
    final live = session('20261111-193823');
    writeStatus(dead, 'running');
    writeStatus(live, 'running');
    final owner = JobLock(data, selfPid: pid);
    expect(owner.acquire(p.basename(live.path)), isTrue);
    final changed = resumer().markInterrupted();
    expect(changed, [p.basename(dead.path)]);
    expect(stateOf(dead), 'interrupted');
    expect(stateOf(live), 'running');
    owner.release();
  });

  test('every unfinished session runs, oldest first, one at a time', () async {
    final a = session('20261111-185105');
    final b = session('20261111-193823');
    final c = session('20261111-212541');
    writeStatus(a, 'interrupted');
    writeStatus(b, 'running');
    // c: never started (no status).
    var overlap = false;
    fake.onStart = (call) {
      if (JobLock(data).holder() == null) overlap = true;
      return ffmpegStart(call);
    };
    expect(await resumer().run(), 0);
    expect([stateOf(a), stateOf(b), stateOf(c)], everyElement('done'));
    expect(overlap, isFalse, reason: 'the lock is held through every job');
    expect(JobLock(data).holder(), isNull);
  });

  test('failed and done are left alone', () async {
    final failed = session('20261111-185105');
    final done = session('20261111-193823');
    writeStatus(failed, 'failed');
    writeStatus(done, 'done');
    expect(await resumer().run(), 0);
    expect(fake.calls, isEmpty);
    expect(stateOf(failed), 'failed');
  });

  test('waiting waits for its retry time', () async {
    final later = session('20261111-185105');
    final due = session('20261111-193823');
    writeStatus(later, 'waiting', retry: 1700000000.0 + 600);
    writeStatus(due, 'waiting', retry: 1700000000.0 - 5);
    expect(await resumer().run(), 0);
    expect(stateOf(later), 'waiting');
    expect(stateOf(due), 'done');
  });

  test('nothing starts while a recording runs', () async {
    final d = session('20261111-185105');
    writeStatus(d, 'interrupted');
    File(p.join(data, 'recording.pid')).writeAsStringSync('$pid');
    expect(await resumer().run(), 0);
    expect(fake.calls, isEmpty);
    expect(stateOf(d), 'interrupted');
  });

  test('nothing starts while another job runs', () async {
    final d = session('20261111-185105');
    writeStatus(d, 'interrupted');
    final owner = JobLock(data, selfPid: pid)..acquire('someone-else');
    expect(await resumer().run(), 0);
    expect(fake.calls, isEmpty);
    owner.release();
  });

  test('a session without a recording or a duration is not started', () async {
    session('20261111-185105', video: false);
    session('20261111-193823', duration: null);
    final errored = session('20261111-212541');
    File(p.join(errored.path, 'session.json')).writeAsStringSync(
      jsonEncode({...fx.meta, 'duration_s': 5, 'error': 'no window'}),
    );
    File(p.join(errored.path, 'recording.mkv')).deleteSync();
    expect(await resumer().run(), 0);
    expect(fake.calls, isEmpty);
  });

  test(
    'an interrupted finish job is relaunched, a missing one is not',
    () async {
      final d = session('20261112-090025');
      final draft = draftPath(fx.target.path, 'alpha', '20261112-090025');
      File(draft)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(kDraft);
      File(p.join(d.path, 'analysis', 'stage3.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'draft': draft, 'todo': 't'}));
      writeStatus(d, 'done');
      opusAnswer = ok('@@@MERGED\n$kDraft@@@REPORT\n# Report\nok\n@@@END\n');
      final games = Directory(gameStateDir(data, 'alpha'))
        ..createSync(recursive: true);
      File(p.join(games.path, 'status.json')).writeAsStringSync(
        jsonEncode({'stage': 1, 'done': 0, 'total': 1, 'state': 'interrupted'}),
      );
      Directory(gameStateDir(data, 'beta')).createSync(recursive: true);
      expect(await resumer().run(), 0);
      final finish = jsonDecode(
        File(p.join(games.path, 'finish.json')).readAsStringSync(),
      ) as Map;
      expect(finish['state'], 'done');
      expect(
        File(p.join(gameStateDir(data, 'beta'), 'finish.json')).existsSync(),
        isFalse,
      );
    },
  );
}
