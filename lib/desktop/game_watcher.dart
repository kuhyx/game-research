/// Ends a session when the game's process exits.
///
/// Polls `/proc/*/cmdline` for Steam's `AppId=<id>` token. The session ends
/// only after the game was seen once and then is gone: Steam may take a
/// while to start it, and a game that never appeared keeps recording until
/// Stop (kuhy may be launching it by hand).
library;

import 'dart:async';
import 'dart:io';

import 'package:game_research/core/proc_match.dart';
import 'package:path/path.dart' as p;

/// Watches one app id.
class GameWatcher {
  /// Creates a watcher over [procRoot] (`/proc`; a temp dir in tests).
  new({this.procRoot = '/proc', this.every = const Duration(seconds: 1)});

  /// The proc filesystem.
  final String procRoot;

  /// Poll interval.
  final Duration every;
  Timer? _timer;

  /// Whether the app has been seen running since [watch].
  bool seen = false;

  /// Whether any process of [appid] runs now.
  bool running(int appid) {
    final dir = Directory(procRoot);
    if (!dir.existsSync()) return false;
    for (final e in dir.listSync()) {
      final pid = p.basename(e.path);
      if (int.tryParse(pid) == null) continue;
      try {
        final bytes = File(p.join(e.path, 'cmdline')).readAsBytesSync();
        if (cmdlineIsApp(String.fromCharCodes(bytes), appid)) return true;
      } on FileSystemException {
        continue; // the process exited while we looked
      }
    }
    return false;
  }

  /// Calls [onExit] once, when [appid] was running and then is gone.
  void watch(int appid, void Function() onExit) {
    cancel();
    seen = false;
    _timer = Timer.periodic(every, (_) {
      final now = running(appid);
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
