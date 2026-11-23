/// Game frame rate per session, from MangoHud.
///
/// MangoHud loads only through Steam launch options (`fps_launch.dart`) and
/// writes one CSV per game run into `<data>/fps-spool/` (set by the
/// app-owned `<data>/mangohud.conf`). At session stop the logs that overlap
/// the session move into `<session>/fps/` and their figures go into
/// `session.json`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/fps.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/fps_launch.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// Spool logs older than this many seconds are deleted.
const int kSpoolKeepS = 7 * 86400;

/// Launch option and log collection for one wrapper.
class FpsSession {
  /// Creates the service.
  const new(this.config, this.sys, this.log);

  /// Settings.
  final Config config;

  /// OS seam (the clock).
  final Sys sys;

  /// Event log.
  final EventLog log;

  FpsLaunch get _launch => FpsLaunch(config, log);

  /// Where MangoHud writes its CSVs.
  String get spoolDir => _launch.spoolDir;

  /// The MangoHud config this app owns (kuhy's own is never touched).
  String get confPath => _launch.confPath;

  /// Puts MangoHud logging into the launch options of every installed game
  /// and [appid] (before its launch). Never throws.
  void prepareLaunch(int appid) => _launch.prepare(appid);

  /// The same for every installed game, at wrapper start.
  void prepareAll() => _launch.prepare();

  /// Moves the spool logs that overlap [from]..[to] (unix seconds) into
  /// `<[session]>/fps/` and returns the figures of the busiest one (a
  /// launcher or a second game may log too); null when there is none. Deletes
  /// spool logs older than [kSpoolKeepS]. Logs one `fps` event.
  Map<String, Object?>? collect(
    Directory session, {
    required double from,
    required double to,
  }) {
    final now = sys.nowUnix();
    final moved = <File>[];
    FpsStats? best;
    var bestFrames = 0;
    final spool = Directory(spoolDir);
    final logs = !spool.existsSync()
        ? <File>[]
        : spool.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.csv'),
          );
    for (final f in logs) {
      final end = f.lastModifiedSync().millisecondsSinceEpoch / 1000;
      if (now - end > kSpoolKeepS) {
        f.deleteSync();
        continue;
      }
      final fpsLog = FpsLog.parse(
        utf8.decode(f.readAsBytesSync(), allowMalformed: true),
      );
      final inside = fpsLog?.overlaps(fileEndUnix: end, from: from, to: to);
      if (!(inside ?? end > from)) continue;
      moved.add(f);
      final frames =
          fpsLog?.frametimesBetween(fileEndUnix: end, from: from, to: to) ??
          const <double>[];
      if (frames.length > bestFrames) {
        bestFrames = frames.length;
        best = fpsStats(frames);
      }
    }
    final names = [for (final f in moved) p.basename(f.path)];
    for (final f in moved) {
      _move(f, Directory(p.join(session.path, 'fps')));
    }
    final stats = best?.toJson();
    log.event('fps', {
      'session': p.basename(session.path),
      'result': stats == null ? 'none' : 'ok',
      'files': names,
      ...?stats,
    });
    return stats;
  }

  /// Session stop: collects the logs from [from] to the session's end
  /// (`ended_unix` in [meta]) and stores the figures as `meta['fps']`.
  void finish(Directory session, double from, Map<String, Object?> meta) {
    meta['fps'] = collect(
      session,
      from: from,
      to: meta['ended_unix']! as double,
    );
  }

  void _move(File file, Directory into) {
    into.createSync(recursive: true);
    final target = p.join(into.path, p.basename(file.path));
    try {
      file.renameSync(target);
      // coverage:ignore-start
    } on FileSystemException {
      // another filesystem (the spool symlinked elsewhere): copy instead
      file
        ..copySync(target)
        ..deleteSync();
    }
    // coverage:ignore-end
  }
}
