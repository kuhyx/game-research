import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/runner.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

void main() {
  late Fixture fx;
  late FakeSys fake;
  var llmFails = false;

  AnalysisRunner runner({int? ownerPid, String? proc}) => AnalysisRunner(
    fx.session.path,
    testConfig(
      fx.root,
      extra: {
        'GAME_RESEARCH_FAKE_LLM': '/fake/llm',
        'GAME_RESEARCH_TODO_CMD': 'faketodo',
        'GAME_RESEARCH_STILL_S': '2',
        'GAME_RESEARCH_PROC': ?proc,
      },
    ),
    fake.sys,
    MockClient((_) async => throw StateError('no network in tests')),
    ownerPid: ownerPid,
  );

  void setup({double? duration = 40, bool templates = true}) {
    fx = Fixture(duration: duration, templates: templates);
    llmFails = false;
    fake = FakeSys()
      ..onStart = ffmpegStart
      ..onRun = (c) {
        switch (c.exe) {
          case 'ffmpeg':
            return ffmpegFake(c);
          case '/fake/llm':
            if (llmFails) return bad();
            return ok(c.args.first == 'opus' ? kAnswer : kCaptionJson);
          case 'faketodo':
            return ok('task-1');
        }
        return bad('no remote', 2);
      };
  }

  setUp(setup);

  test('a missing session.json is a usage error: exit 2', () async {
    File(p.join(fx.session.path, 'session.json')).deleteSync();
    expect(await runner().run(), 2);
    expect(
      Directory(p.join(fx.session.path, 'analysis')).existsSync(),
      isFalse,
    );
  });

  test('a lock held by a live pid is exit 3 and stays', () async {
    final lock = fx.out('lock')
      ..createSync(recursive: true)
      ..writeAsStringSync('$pid');
    // An analyzer process by its cmdline (a bare live pid proves nothing:
    // after a reboot it may be any program).
    final proc = Directory(p.join(fx.root.path, 'proc', '$pid'))
      ..createSync(recursive: true);
    File(p.join(proc.path, 'cmdline')).writeAsStringSync(
      '/x/bin/game_research_analyze\u0000${fx.session.path}\u0000',
    );
    final procRoot = p.dirname(proc.path);
    expect(await runner(proc: procRoot).run(), 3);
    expect(lock.readAsStringSync(), '$pid');
    expect(fake.calls, isEmpty);
  });

  test(
    'a stale lock whose pid now runs another program is taken over',
    () async {
      // kuhy, 2026-11-12: three jobs died with the 23:10 shutdown and left
      // lock files; after the reboot those pids may belong to anything.
      fx.out('lock')
        ..createSync(recursive: true)
        ..writeAsStringSync('$pid');
      expect(
        await runner().run(),
        0,
        reason: 'this test process is no analyzer',
      );
    },
  );

  test('a stale or garbled lock is taken over', () async {
    final lock = fx.out('lock')
      ..createSync(recursive: true)
      ..writeAsStringSync('2147483000');
    expect(await runner(ownerPid: 123).run(), 0);
    lock.writeAsStringSync('not a pid');
    expect(await runner().run(), 0);
    expect(
      Link(p.join(fx.root.path, 'data', 'analysis.lock')).existsSync(),
      isFalse,
      reason: 'released at the end',
    );
  });

  test('all three stages: exit 0, status done, drafts, no lock', () async {
    expect(await runner().run(), 0);
    expect(fx.status, containsPair('state', 'done'));
    expect(fx.status, containsPair('stage', 3));
    expect(fx.out('captions.jsonl').readAsLinesSync(), hasLength(1));
    expect(
      File(
        draftPath(
          fx.target.path,
          'alpha',
          sessionStamp(p.basename(fx.session.path)),
        ),
      ).existsSync(),
      isTrue,
    );
  });

  test('a rerun resumes: nothing left to do, nothing run', () async {
    await runner().run();
    fake.calls.clear();
    expect(await runner().run(), 0);
    expect(fake.calls, isEmpty);
  });

  test('--force clears every output and redoes the work', () async {
    await runner().run();
    fx.out('junk.txt').writeAsStringSync('old');
    Directory(p.join(fx.session.path, 'analysis', 'old_dir')).createSync();
    fake.calls.clear();
    expect(await runner().run(force: true), 0);
    expect(fx.out('junk.txt').existsSync(), isFalse);
    expect(
      Directory(p.join(fx.session.path, 'analysis', 'old_dir')).existsSync(),
      isFalse,
    );
    expect(fake.of('ffmpeg'), isNotEmpty);
    expect(fake.of('/fake/llm'), isNotEmpty);
    expect(fx.status, containsPair('state', 'done'));
  });

  test('a session without a duration fails stage 1 closed', () async {
    setup(duration: null);
    expect(await runner().run(), 1);
    expect(fx.status, containsPair('state', 'failed'));
    expect(fx.status, containsPair('stage', 1));
    expect(fx.status['error'], contains('no duration_s'));
    expect(
      Link(p.join(fx.root.path, 'data', 'analysis.lock')).existsSync(),
      isFalse,
    );
  });

  test('a session without markers still runs', () async {
    File(p.join(fx.session.path, 'markers.jsonl')).deleteSync();
    expect(await runner().run(), 0);
  });

  test('ffmpeg failing fails stage 1', () async {
    fake.onStart = (_) => FakeProcess(exit: 1, stderrText: 'corrupt');
    expect(await runner().run(), 1);
    expect(fx.status, containsPair('stage', 1));
    expect(fx.status['error'], contains('corrupt'));
  });

  test('frames no tier can caption fail stage 2', () async {
    llmFails = true;
    expect(await runner().run(), 1);
    expect(fx.status, containsPair('stage', 2));
    expect(fx.status['error'], contains('no tier captioned'));
    llmFails = false;
    expect(await runner().run(), 0, reason: 'the failed job resumes');
  });

  test('a target without templates fails stage 3', () async {
    setup(templates: false);
    expect(await runner().run(), 1);
    expect(fx.status, containsPair('stage', 3));
    expect(fx.status['state'], 'failed');
    expect(
      jsonDecode(fx.out('status.json').readAsStringSync()),
      containsPair('error', contains('no questions template')),
    );
  });
}
