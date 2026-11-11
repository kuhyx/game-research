/// Ends a session when the game's processes exit.
///
/// Polls `/proc` for the game tree (Steam's reaper carries `AppId=<id>`,
/// every process `SteamAppId=<id>`). The session ends only after the game
/// was seen once and then is gone: Steam may take a while to start it, and a
/// game that never appeared keeps recording until Stop (kuhy may be
/// launching it by hand). A tick whose /proc listing fails is skipped: an
/// unreadable /proc is not a game exit.
library;

import 'dart:async';
import 'dart:io';

import 'package:game_research/desktop/proc_scan.dart';

/// Watches one app id.
class GameWatcher {
  /// Creates a watcher over [procRoot] (`/proc`; a temp dir in tests);
  /// [list] replaces the directory lister in tests.
  new({
    this.procRoot = '/proc',
    this.every = const Duration(seconds: 1),
    DirLister? list,
  }) : _scan = ProcScan(procRoot, list: list ?? listDir);

  /// The proc filesystem.
  final String procRoot;

  /// Poll interval.
  final Duration every;
  final ProcScan _scan;
  Timer? _timer;

  /// Whether the app has been seen running since [watch].
  bool seen = false;

  /// Whether any process of [appid] runs now. Throws
  /// [FileSystemException] when /proc cannot be listed.
  bool running(int appid) => _scan.gamePids(appid).isNotEmpty;

  /// Calls [onExit] once, when [appid] was running and then is gone.
  void watch(int appid, void Function() onExit) {
    cancel();
    seen = false;
    _timer = Timer.periodic(every, (_) {
      final bool now;
      try {
        now = running(appid);
      } on FileSystemException {
        return;
      }
      if (now) {
        seen = true;
      } else if (seen) {
        cancel();
        onExit();
      }
    });
  }

  /// Stops watching.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
