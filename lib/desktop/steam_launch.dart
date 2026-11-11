/// Launching a game through Steam and finding its window.
///
/// No client running: Steam starts in its own `systemd-run --user` unit with
/// the rungameid URI, so it outlives a wrapper restart (a child of the
/// wrapper unit would die with it). A client running: `steam <uri>` hands
/// the URI over and exits. Both log the command and its exit code.
library;

import 'dart:async';
import 'dart:io';

import 'package:game_research/core/steam.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/proc_scan.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/sys.dart';

/// Starts a game through Steam.
class GameLauncher {
  /// Creates the launcher; [timeout] bounds the Steam command.
  const new(
    this.config,
    this.sys,
    this.scan,
    this.log, {
    this.timeout = const Duration(seconds: 30),
  });

  /// Longest wait for the Steam command (a handoff exits at once).
  final Duration timeout;

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  /// /proc reader.
  final ProcScan scan;

  /// Event log.
  final EventLog log;

  /// The Steam unit PlayStudy starts, one per wrapper port.
  String get unit => 'playstudy-steam-${config.port}';

  /// The argv that launches [appid] given the client's [pid] (null = down).
  List<String> command(int appid, int? pid) {
    final uri = runGameUri(appid);
    if (pid != null) return [config.steamCmd, uri];
    return [
      'systemd-run',
      '--user',
      '--collect',
      '--quiet',
      '--unit',
      unit,
      '--setenv=DISPLAY=${config.display}',
      if (config.xauthority.isNotEmpty)
        '--setenv=XAUTHORITY=${config.xauthority}',
      for (final e in config.steamEnv) '--setenv=$e',
      config.steamCmd,
      uri,
    ];
  }

  /// Launches [appid]; throws [StartError] when the command fails.
  Future<void> launch(int appid) async {
    final pid = scan.steamClient(config.steamPidFile);
    log.event('steam_client', {'pid': pid});
    final cmd = command(appid, pid);
    final ProcessResult r;
    try {
      r = await sys
          .run(
            cmd.first,
            cmd.sublist(1),
            environment: {'DISPLAY': config.display},
          )
          .timeout(timeout);
    } on ProcessException catch (e) {
      log.event('launch', {'cmd': cmd, 'exit_code': null, 'error': e.message});
      throw StartError('steam did not start: ${e.message}');
    } on TimeoutException {
      log.event('launch', {'cmd': cmd, 'exit_code': null, 'error': 'timeout'});
      throw StartError('steam did not answer in ${timeout.inSeconds} s');
    }
    final err = '${r.stderr}'.trim();
    log.event('launch', {'cmd': cmd, 'exit_code': r.exitCode, 'stderr': err});
    if (r.exitCode != 0) {
      throw StartError('steam launch exited ${r.exitCode}: $err');
    }
  }
}

/// One game window: its X id and the pid that owns it.
typedef WindowHit = ({int pid, String window});

/// Finds a visible X window owned by a process of the game.
class GameWindow {
  /// Creates the finder.
  const new(this.config, this.sys, this.scan);

  /// Settings (the display).
  final Config config;

  /// OS seam (`xdotool`).
  final Sys sys;

  /// /proc reader.
  final ProcScan scan;

  /// Smallest side of a game window; Wine's helpers (IME 1x1, WineD3D
  /// 111x1, DXGI 113x2, Proton's "Steam" 400x300) are smaller.
  static const minSide = 480;

  Future<String?> _search(List<String> by) async {
    final r = await sys.run(
      'xdotool',
      ['search', '--onlyvisible', ...by, 'getwindowgeometry', '--shell', '%@'],
      environment: {'DISPLAY': config.display},
    );
    return r.exitCode == 0 ? bigWindow('${r.stdout}') : null;
  }

  /// The first visible, game-sized window of [appid], or null. Proton
  /// names every window's class `steam_app_<id>` (its `_NET_WM_PID` is a
  /// Wine thread id, not a process); a native game is found by the pids of
  /// its tree (pid 0 = found by class). Walks the window tree, so it needs
  /// no window manager.
  Future<WindowHit?> find(int appid) async {
    final byClass = await _search(['--class', '^steam_app_$appid\$']);
    if (byClass != null) return (pid: 0, window: byClass);
    final List<int> pids;
    try {
      pids = scan.gamePids(appid);
    } on FileSystemException {
      return null; // /proc unreadable this tick; the next poll retries
    }
    for (final pid in pids) {
      // xdotool takes the next word as the pattern. '' also matches the
      // root window (no _NET_WM_PID filter there); '.' needs a name or
      // class, which every game window has and root has not.
      final id = await _search(['--pid', '$pid', '.']);
      if (id != null) return (pid: pid, window: id);
    }
    return null;
  }
}

/// The first window in `xdotool getwindowgeometry --shell` [output] whose
/// sides are both at least [GameWindow.minSide], or null.
String? bigWindow(String output) {
  String? id;
  int? width;
  for (final line in output.split('\n')) {
    final [key, value] = [...line.split('='), '', ''].take(2).toList();
    if (key == 'WINDOW') id = value;
    if (key == 'WIDTH') width = int.tryParse(value);
    if (key == 'HEIGHT') {
      final height = int.tryParse(value) ?? 0;
      if ((width ?? 0) >= GameWindow.minSide && height >= GameWindow.minSide) {
        return id;
      }
    }
  }
  return null;
}
