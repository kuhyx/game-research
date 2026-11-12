/// The analysis job: stages 1-3 in order, each resumable, progress in
/// `analysis/status.json`. Exit codes adjudicate ([JobExit]): 0 done, 1 a
/// stage failed (status says why), 2 bad arguments, 3 this job already runs,
/// 4 waiting (queued behind another job, or a usage limit).
///
/// One job runs at a time machine-wide ([runLocked]); a job that finds the
/// machine busy records `waiting` and exits, and the next job to finish (or
/// the resume timer) starts it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/analysis/job.dart';
import 'package:game_research/analysis/stage1.dart';
import 'package:game_research/analysis/stage2.dart';
import 'package:game_research/analysis/stage3.dart';
import 'package:game_research/analysis/tiers.dart';
import 'package:game_research/core/captions.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/sampling.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/recording_flag.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Runs the whole job on session folder [dir].
class AnalysisRunner {
  /// Creates the runner.
  new(
    this.dir,
    this.config,
    this.sys,
    this.client, {
    this.ownerPid,
    this.recordingPoll = const Duration(seconds: 5),
  });

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

  /// How often a job paused by a recording checks again.
  final Duration recordingPoll;

  String get _a => p.join(dir, 'analysis');

  /// Waits while a PlayStudy recording runs: the game gets the machine.
  Future<void> _gate() => RecordingFlag(
    config.dataDir,
    procRoot: config.procRoot,
  ).waitClear(recordingPoll);

  /// A forced rerun that got queued leaves this file; the run that finally
  /// starts clears the outputs (and with them the file) once.
  File get _forceFlag => File(p.join(_a, 'force'));

  /// Runs every stage not yet done ([force]: redo all). Returns the exit code.
  /// A forced run queued behind another job remembers its force for the drain.
  Future<int> run({bool force = false}) async {
    final metaFile = File(p.join(dir, 'session.json'));
    if (!metaFile.existsSync()) return JobExit.usage;
    Directory(_a).createSync(recursive: true);
    final status = StatusWriter(
      File(p.join(_a, 'status.json')),
      sys,
      () => sessionUsage(dir),
    );
    final redo = force || _forceFlag.existsSync();
    var started = false;
    final code = await runLocked(
      job: p.basename(dir),
      config: config,
      status: status,
      ownerPid: ownerPid,
      body: (stage) async {
        started = true;
        if (redo) _clear();
        final meta =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, Object?>;
        final markersFile = File(p.join(dir, 'markers.jsonl'));
        final markers = markersFile.existsSync()
            ? parseMarkers(markersFile.readAsStringSync())
            : <Marker>[];
        final duration = (meta['duration_s'] as num?)?.toDouble();
        if (duration == null) {
          throw StateError('session.json has no duration_s');
        }
        await _gate();
        status.write(1, 0, 1, StageState.running);
        final frames =
            await Stage1(dir, sys, stillS: config.stillS, gate: _gate).run(
              durationS: duration,
              markers: markers,
              progress: (d, t) => status.write(1, d, t, StageState.running),
            );
        stage.value = 2;
        // Only the frames stage 3 shows Opus get a caption.
        final picked = pickSynthesisFrames(frames, synthesisFrameCap(duration));
        status.write(2, 0, picked.length, StageState.running);
        final failed = await Stage2(
          dir,
          captionTiers(config, sys, client),
          gate: _gate,
        ).run(picked, (d, t) => status.write(2, d, t, StageState.running));
        if (failed.isNotEmpty) {
          final why = 'no tier captioned ${failed.join(', ')}';
          if (isRateLimited(why)) throw WaitingError(why);
          throw StateError(why);
        }
        stage.value = 3;
        await _gate();
        status.write(3, 0, 1, StageState.running);
        await Stage3(dir, config, sys).run(meta, frames);
        status.write(3, 1, 1, StageState.done);
      },
    );
    if (redo && !started && code == JobExit.waiting) {
      _forceFlag.writeAsStringSync('');
    }
    return code;
  }

  /// Removes every stage output (a forced rerun), keeping the folder.
  void _clear() {
    for (final e in Directory(_a).listSync()) {
      e.deleteSync(recursive: true);
    }
  }
}
