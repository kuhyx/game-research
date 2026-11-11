/// The JSON-lines event log: one object per step (app start, picker
/// contents, launch command and exit code, Steam and game pids, the game
/// window, recording start and stop, every error), so an agent or kuhy can
/// replay what the wrapper did. Path: `Config.logFile`
/// (`~/data/game-research/playstudy.jsonl`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/desktop/sys.dart';

/// Appends events to one file.
class EventLog {
  /// Logs to [path]; [clock] stamps each line (real time by default, so a
  /// test's fake clock is not advanced by logging).
  const new(this.path, {this.clock = unixNow});

  /// The `.jsonl` file.
  final String path;

  /// Unix seconds.
  final double Function() clock;

  /// Appends `{"t": .., "event": [name], ...fields}`. A log that cannot be
  /// written goes to stderr (the unit's journal) instead of failing a step.
  void event(String name, [Map<String, Object?> fields = const {}]) {
    final line = jsonEncode({'t': clock(), 'event': name, ...fields});
    try {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } on FileSystemException {
      stderr.writeln(line);
    }
  }

  /// The last [n] lines (fewer when the log is shorter or missing).
  List<String> tail(int n) {
    final f = File(path);
    if (!f.existsSync()) return const [];
    final lines = const LineSplitter().convert(f.readAsStringSync());
    return lines.sublist(lines.length > n ? lines.length - n : 0);
  }
}
