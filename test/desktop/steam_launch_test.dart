import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/proc_scan.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/steam_launch.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory root;
  late Directory proc;
  late FakeSys fake;
  late EventLog log;

  GameLauncher launcher([Map<String, String> extra = const {}]) {
    final config = testConfig(
      root,
      extra: {
        'GAME_RESEARCH_STEAM_PID': p.join(root.path, 'steam.pid'),
        ...extra,
      },
    );
    log = EventLog(config.logFile);
    return GameLauncher(config, fake.sys, ProcScan(proc.path), log);
  }

  setUp(() {
    root = tempDir();
    log = EventLog(p.join(root.path, 'log.jsonl'));
    proc = Directory(p.join(root.path, 'proc'))..createSync();
    fake = FakeSys();
  });

  test('the unit command carries XAUTHORITY and the extra Steam env', () {
    final config = testConfig(
      root,
      extra: {
        'XAUTHORITY': '/x/auth',
        'GAME_RESEARCH_STEAM_ENV': 'PROTON_USE_WINED3D=1 SDL_AUDIODRIVER=dummy',
      },
    );
    final cmd = GameLauncher(
      config,
      fake.sys,
      ProcScan(proc.path),
      log,
    ).command(5, null);
    expect(
      cmd,
      containsAllInOrder([
        '--setenv=DISPLAY=:99',
        '--setenv=XAUTHORITY=/x/auth',
        '--setenv=PROTON_USE_WINED3D=1',
        '--setenv=SDL_AUDIODRIVER=dummy',
        'steam',
        'steam://rungameid/5',
      ]),
    );
  });

  test('a hung Steam command is a StartError after the timeout', () async {
    final l = launcher();
    final hung = GameLauncher(
      l.config,
      Sys(
        run: (exe, args, {environment, workingDirectory}) =>
            Completer<ProcessResult>().future,
      ),
      l.scan,
      l.log,
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(hung.launch(1), throwsA(isA<StartError>()));
    final last = jsonDecode(log.tail(1).single) as Map<String, Object?>;
    expect(last['error'], 'timeout');
  });

  group('GameWindow', () {
    // Wine's helpers (1x1 IME, 111x1 WineD3D) come first; the game window
    // is the big one.
    const geometry =
        'WINDOW=99\nX=40\nY=40\nWIDTH=400\nHEIGHT=300\nSCREEN=0\n'
        'WINDOW=100\nX=0\nY=0\nWIDTH=1920\nHEIGHT=1080\nSCREEN=0\n';

    test('no game process and no Proton window: one class query', () async {
      final w = GameWindow(testConfig(root), fake.sys, ProcScan(proc.path));
      expect(await w.find(7), isNull);
      expect(fake.calls.single.args, [
        'search',
        '--onlyvisible',
        '--class',
        r'^steam_app_7$',
        'getwindowgeometry',
        '--shell',
        '%@',
      ]);
    });

    test("Proton's steam_app class finds the game window", () async {
      // 2026-11-11 real run: Librarian's window carried a Wine thread id
      // as _NET_WM_PID, so only the class matched.
      fake.onRun = (c) => c.args.contains('--class') ? ok(geometry) : bad();
      final w = GameWindow(testConfig(root), fake.sys, ProcScan(proc.path));
      expect(await w.find(7), (pid: 0, window: '100'));
    });

    test('the first process with a visible window wins', () async {
      for (final pid in ['10', '11']) {
        Directory(p.join(proc.path, pid)).createSync();
        File(p.join(proc.path, pid, 'environ'))
            .writeAsStringSync('SteamAppId=7\x00');
      }
      fake.onRun = (c) => c.args.contains('11') ? ok(geometry) : bad();
      // (the class query comes first and finds nothing here)
      final w = GameWindow(testConfig(root), fake.sys, ProcScan(proc.path));
      expect(await w.find(7), (pid: 11, window: '100'));
      expect(fake.calls.last.args, [
        'search',
        '--onlyvisible',
        '--pid',
        '11',
        'getwindowgeometry',
        '--shell',
        '%@',
      ]);
      expect(fake.calls.first.env, {'DISPLAY': ':99'});
    });

    test('a /proc listing error is no window yet', () async {
      final w = GameWindow(
        testConfig(root),
        fake.sys,
        ProcScan(
          proc.path,
          list: (_) => throw const PathNotFoundException('x', OSError()),
        ),
      );
      expect(await w.find(7), isNull);
    });

    test('only helper-sized windows are no window yet', () async {
      Directory(p.join(proc.path, '12')).createSync();
      File(p.join(proc.path, '12', 'cmdline'))
          .writeAsStringSync('reaper\x00AppId=7');
      fake.onRun = (_) =>
          ok('WINDOW=5\nWIDTH=1\nHEIGHT=1\nWINDOW=6\nWIDTH=x\n');
      final w = GameWindow(testConfig(root), fake.sys, ProcScan(proc.path));
      expect(await w.find(7), isNull);
    });

    test('xdotool exiting 0 with nothing printed is no window', () async {
      Directory(p.join(proc.path, '12')).createSync();
      File(p.join(proc.path, '12', 'cmdline'))
          .writeAsStringSync('reaper\x00AppId=7');
      fake.onRun = (_) => ok();
      final w = GameWindow(testConfig(root), fake.sys, ProcScan(proc.path));
      expect(await w.find(7), isNull);
    });
  });
}
