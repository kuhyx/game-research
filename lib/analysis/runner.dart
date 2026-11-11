/// The analysis job: stages 1-3 in order, each resumable, progress in
/// `analysis/status.json`. Exit codes adjudicate: 0 done, 1 a stage failed
/// (status says why), 2 bad arguments, 3 another job holds the lock.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/analysis/stage1.dart';
import 'package:game_research/analysis/stage2.dart';
import 'package:game_research/analysis/stage3.dart';
import 'package:game_research/analysis/tiers.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Runs the whole job on session folder [dir].
class AnalysisRunner {
  /// Creates the runner.
  new(this.dir, this.config, this.sys, this.client, {this.ownerPid});

  /// Session folder.
  final String dir;

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  /// HTTP client for OmniRoute and ollama.
  final http.Client client;

  /// The lock owner's pid; defaults to this process.
  final int? ownerPid;

  String get _a => p.join(dir, 'analysis');

  void _status(int stage, int done, int total, StageState state, [String? e]) {
    File(p.join(_a, 'status.json')).writeAsStringSync(
      jsonEncode(
        AnalysisStatus(
          stage: stage,
          done: done,
          total: total,
          state: state,
          error: e,
        ).toJson(),
      ),
    );
  }

  /// Takes `analysis/lock`; false when a live job holds it.
  bool _lock() {
    final lock = File(p.join(_a, 'lock'));
    if (lock.existsSync()) {
      final owner = int.tryParse(lock.readAsStringSync().trim());
      if (owner != null && Directory('/proc/$owner').existsSync()) return false;
    }
    lock.writeAsStringSync('${ownerPid ?? pid}');
    return true;
  }

  /// Runs every stage not yet done ([force]: redo all). Returns the exit code.
  Future<int> run({bool force = false}) async {
    final metaFile = File(p.join(dir, 'session.json'));
    if (!metaFile.existsSync()) return 2;
    Directory(_a).createSync(recursive: true);
    if (!_lock()) return 3;
    var stage = 1;
    try {
      if (force) _clear();
      final meta =
          jsonDecode(metaFile.readAsStringSync()) as Map<String, Object?>;
      final markersFile = File(p.join(dir, 'markers.jsonl'));
      final markers = markersFile.existsSync()
          ? parseMarkers(markersFile.readAsStringSync())
          : <Marker>[];
      final duration = (meta['duration_s'] as num?)?.toDouble();
      if (duration == null) throw StateError('session.json has no duration_s');
      _status(1, 0, 1, StageState.running);
      final frames = await Stage1(dir, sys, stillS: config.stillS).run(
        durationS: duration,
        markers: markers,
        progress: (d, t) => _status(1, d, t, StageState.running),
      );
      stage = 2;
      _status(2, 0, frames.length, StageState.running);
      final failed = await Stage2(
        dir,
        captionTiers(config, sys, client),
      ).run(frames, (d, t) => _status(2, d, t, StageState.running));
      if (failed.isNotEmpty) {
        throw StateError('no tier captioned ${failed.join(', ')}');
      }
      stage = 3;
      _status(3, 0, 1, StageState.running);
      await Stage3(dir, config, sys).run(meta, frames);
      _status(3, 1, 1, StageState.done);
      return 0;
    } on Object catch (e) {
      _status(stage, 0, 1, StageState.failed, '$e');
      return 1;
    } finally {
      File(p.join(_a, 'lock')).deleteSync();
    }
  }

  /// Removes every stage output (a forced rerun), keeping the folder.
  void _clear() {
    for (final e in Directory(_a).listSync()) {
      if (p.basename(e.path) == 'lock') continue;
      e.deleteSync(recursive: true);
    }
  }
}
