import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/session_store.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory root;
  late FakeSys fake;
  late Directory session;

  AnalysisLauncher launcher(Map<String, String> extra) =>
      AnalysisLauncher(testConfig(root, extra: extra), fake.sys);

  setUp(() {
    root = tempDir();
    fake = FakeSys(now: 1700000000.5);
    session = Directory(p.join(root.path, 's'))..createSync();
  });

  test('the analyzer is the bundle built beside the wrapper', () {
    final config = testConfig(root, extra: {'GAME_RESEARCH_REPO': '/repo'});
    expect(
      AnalysisLauncher(config, fake.sys).analyzer,
      '/repo/build/analyze/bundle/bin/game_research_analyze',
    );
  });

  group('inline', () {
    test('starts the analyzer detached', () async {
      expect(await launcher({}).launch(session), isTrue);
      final call = fake.calls.single;
      expect(call.args, [session.path]);
      expect(call.mode, ProcessStartMode.detached);
    });

    test('force adds --force; a start failure returns false', () async {
      await launcher({}).launch(session, force: true);
      expect(fake.calls.single.args, [session.path, '--force']);
      fake.onStart = (_) => throw const ProcessException('x', []);
      expect(await launcher({}).launch(session), isFalse);
    });
  });

  group('systemd', () {
    test('a transient user unit carries the env and the dir', () async {
      final l = launcher({
        'GAME_RESEARCH_ANALYZE': 'systemd',
        'GAME_RESEARCH_REPO': '/repo',
      });
      expect(await l.launch(session, force: true), isTrue);
      final call = fake.calls.single;
      expect(call.exe, 'systemd-run');
      expect(call.args, containsAllInOrder(['--user', '--collect', '--quiet']));
      expect(call.args, contains('game-research-analyze-1700000000500'));
      expect(call.args, contains('WorkingDirectory=/repo'));
      expect(call.args, contains('--setenv=HOME=${root.path}'));
      expect(
        call.args.firstWhere((a) => a.startsWith('--setenv=PATH=')),
        '--setenv=PATH=${root.path}/.local/bin:/usr/local/bin:/usr/bin',
      );
      expect(call.args, contains('--setenv=GAME_RESEARCH_DISPLAY=:99'));
      expect(call.args.sublist(call.args.length - 3), [
        l.analyzer,
        session.path,
        '--force',
      ]);
    });

    test('a failing systemd-run returns false', () async {
      fake.onRun = (_) => bad('denied');
      final l = launcher({'GAME_RESEARCH_ANALYZE': 'systemd'});
      expect(await l.launch(session), isFalse);
    });
  });
}
