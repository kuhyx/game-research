/// `<data>/recording.pid`: up while a recording runs, so PlayStudy's own
/// analysis job waits instead of competing with the game (kuhy, 2026-11-11).
/// It never touches other programs. A dead pid (a crashed wrapper) leaves
/// no block, the same rule as `analysis/lock`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The flag file in [dataDir].
class RecordingFlag {
  /// Creates the flag; [procRoot] is where pids are looked up.
  const new(this.dataDir, {this.procRoot = '/proc'});

  /// The data folder (`GAME_RESEARCH_DATA`).
  final String dataDir;

  /// `/proc`.
  final String procRoot;

  /// The file.
  File get file => File(p.join(dataDir, 'recording.pid'));

  /// Up, owned by this process.
  void raise() {
    Directory(dataDir).createSync(recursive: true);
    file.writeAsStringSync('$pid');
  }

  /// Down (idempotent).
  void lower() {
    if (file.existsSync()) file.deleteSync();
  }

  /// Up and its owner alive.
  bool get live {
    if (!file.existsSync()) return false;
    final owner = int.tryParse(file.readAsStringSync().trim());
    return owner != null && Directory('$procRoot/$owner').existsSync();
  }

  /// Returns once no recording runs, checking every [poll].
  Future<void> waitClear(Duration poll) async {
    while (live) {
      await Future<void>.delayed(poll);
    }
  }
}
