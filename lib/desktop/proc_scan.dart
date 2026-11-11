/// Reading `/proc`: is the Steam client up, which processes are the game.
library;

import 'dart:io';

import 'package:game_research/core/proc_match.dart';
import 'package:path/path.dart' as p;

/// Lists a directory (replaced in tests to simulate /proc races).
typedef DirLister = List<FileSystemEntity> Function(Directory dir);

/// The real lister.
List<FileSystemEntity> listDir(Directory dir) => dir.listSync();

/// A scan of one proc filesystem.
class ProcScan {
  /// Scans [root] (`/proc`; a temp dir in tests).
  const new(this.root, {this.list = listDir});

  /// The proc filesystem.
  final String root;

  /// Directory lister.
  final DirLister list;

  /// The numeric entries of [root]. Listing /proc throws when a process
  /// exits mid-listing (seen 2026-11-11 as Wine's helpers quit), so it is
  /// retried; a listing that keeps failing throws [FileSystemException].
  List<String> _pids() {
    for (var attempt = 1; ; attempt++) {
      try {
        return [
          for (final e in list(Directory(root)))
            if (int.tryParse(p.basename(e.path)) != null) p.basename(e.path),
        ];
      } on FileSystemException {
        if (attempt == 5) rethrow;
      }
    }
  }

  String? _read(String pid, String name) {
    try {
      return String.fromCharCodes(
        File(p.join(root, pid, name)).readAsBytesSync(),
      );
    } on FileSystemException {
      return null; // gone, or not ours
    }
  }

  /// The Steam client's pid from [pidFile] when that process still runs
  /// and is Steam; null otherwise (Steam leaves a stale file on exit).
  int? steamClient(String pidFile) {
    final f = File(pidFile);
    if (!f.existsSync()) return null;
    final pid = int.tryParse(f.readAsStringSync().trim());
    if (pid == null) return null;
    final cmd = _read('$pid', 'cmdline');
    return cmd != null && cmd.toLowerCase().contains('steam') ? pid : null;
  }

  /// Every process of [appid]: Steam puts `SteamAppId=<id>` in the
  /// environment of the whole game tree (Proton's wine processes included,
  /// whose command lines lack the reaper's `AppId=` token).
  /// Throws [FileSystemException] only when /proc cannot be listed.
  List<int> gamePids(int appid) {
    if (!Directory(root).existsSync()) return const [];
    final token = 'SteamAppId=$appid';
    return [
      for (final pid in _pids())
        if ((_read(pid, 'environ') ?? '').split('\x00').contains(token) ||
            cmdlineIsApp(_read(pid, 'cmdline') ?? '', appid))
          int.parse(pid),
    ]..sort();
  }

  /// Whether a process of [appid] runs; null when /proc cannot be listed.
  bool? running(int appid) {
    try {
      return gamePids(appid).isNotEmpty;
    } on FileSystemException {
      return null;
    }
  }
}
