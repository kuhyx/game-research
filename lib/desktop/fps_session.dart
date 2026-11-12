/// Game frame rate per session, from MangoHud.
///
/// Two mechanisms feed one spool (`<data>/fps-spool/`, one CSV per game run,
/// set by the app-owned `<data>/mangohud.conf`): the MangoHud layer loaded
/// for the whole desktop session (`install.sh --step fps`), and a Steam
/// launch option for the researched game, written into `localconfig.vdf`
/// before the launch, and only while no Steam client runs (Steam rewrites the
/// file on exit and would drop the edit). At session stop the logs that
/// overlap the session move into `<session>/fps/` and their figures go into
/// `session.json`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/fps.dart';
import 'package:game_research/core/steam_vdf.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/proc_scan.dart';
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

  /// Where MangoHud writes its CSVs.
  String get spoolDir => p.join(config.dataDir, 'fps-spool');

  /// The MangoHud config this app owns (kuhy's own is never touched).
  String get confPath => p.join(config.dataDir, 'mangohud.conf');

  void _launchEvent(int appid, String result, [String? message]) => log.event(
    'fps_launch_option',
    {'appid': appid, 'result': result, 'message': ?message},
  );

  /// Renders `tool/mangohud.conf.in` into [confPath].
  void _writeConf() {
    final template = File(p.join(config.repo, 'tool', 'mangohud.conf.in'))
        .readAsStringSync();
    final text = template.replaceAll('@SPOOL@', spoolDir);
    Directory(spoolDir).createSync(recursive: true);
    final conf = File(confPath);
    if (!conf.existsSync() || conf.readAsStringSync() != text) {
      conf.writeAsStringSync(text);
    }
  }

  /// Puts MangoHud logging into [appid]'s Steam launch options (before the
  /// launch). Never throws: every outcome is an `fps_launch_option` event.
  void prepareLaunch(int appid) {
    final steam = ProcScan(config.procRoot).steamClient(config.steamPidFile);
    if (steam != null) return _launchEvent(appid, 'skipped steam running');
    final users = Directory(p.join(config.steamRoot, 'userdata'));
    final files =
        [
            if (users.existsSync())
              for (final d in users.listSync().whereType<Directory>())
                File(p.join(d.path, 'config', 'localconfig.vdf')),
          ].where((f) => f.existsSync()).toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) return _launchEvent(appid, 'skipped no localconfig');
    try {
      _writeConf();
    } on FileSystemException catch (e) {
      return _launchEvent(appid, 'error', 'mangohud.conf: ${e.message}');
    }
    for (final f in files) {
      try {
        final edit = addMangoHud(f.readAsStringSync(), appid, confPath);
        if (edit.result == 'added') _replace(f, edit.text);
        _launchEvent(appid, edit.result);
      } on FormatException catch (e) {
        _launchEvent(appid, 'error', e.message);
      } on FileSystemException catch (e) {
        _launchEvent(appid, 'error', e.message);
      }
    }
  }

  /// Writes [text] over [file] through a rename, keeping the first original
  /// as `<file>.game-research.bak`.
  void _replace(File file, String text) {
    final bak = File('${file.path}.game-research.bak');
    if (!bak.existsSync()) file.copySync(bak.path);
    File('${file.path}.game-research.tmp')
      ..writeAsStringSync(text)
      ..renameSync(file.path);
  }

  /// Moves the spool logs that overlap [from]..[to] (unix seconds) into
  /// `<[session]>/fps/` and returns the figures of the busiest one (the
  /// game: other Vulkan programs log too); null when there is none. Deletes
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
