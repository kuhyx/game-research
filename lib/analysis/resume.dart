/// `game_research_analyze --resume-all`: what the systemd timer runs every 15
/// minutes (and after each boot) so analysis survives shutdown, reboot, crash
/// and usage limits.
///
/// It relaunches every unfinished session and finish job, one at a time, and
/// never while a recording runs. Unfinished means: running but its process
/// died (marked `interrupted`), `interrupted`, `waiting` with its retry time
/// passed, or a stopped session whose analysis never started. `failed` is
/// never retried by itself (a bad model answer would cost a call every time)
/// and `done` is done.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/analysis/finish.dart';
import 'package:game_research/analysis/job.dart';
import 'package:game_research/analysis/job_lock.dart';
import 'package:game_research/analysis/retention.dart';
import 'package:game_research/analysis/runner.dart';
import 'package:game_research/core/safe_json.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/core/usage.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/recording_flag.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// One job that could be (re)launched.
class _Candidate {
  const new(this.id, this.statusFile, this.launch);

  /// The job id the lock uses.
  final String id;

  /// Its `status.json`.
  final File statusFile;

  /// Runs it; returns the exit code.
  final Future<int> Function() launch;

  /// The status on disk; null when missing or damaged (then the job counts as
  /// never started and runs again).
  AnalysisStatus? get status {
    final json = readJsonObject(statusFile);
    if (json == null) return null;
    try {
      return AnalysisStatus.fromJson(json);
    } on Object {
      return null;
    }
  }
}

/// Relaunches unfinished jobs.
class ResumeAll {
  /// Creates the resumer.
  new(
    this.config,
    this.sys,
    this.client, {
    this.recordingPoll = const Duration(seconds: 5),
    this.runSession,
  });

  /// Settings.
  final Config config;

  /// Test seam: runs one session folder's job instead of [AnalysisRunner].
  final Future<int> Function(String dir)? runSession;

  /// OS seam.
  final Sys sys;

  /// HTTP client for the caption tiers.
  final http.Client client;

  /// How often a job paused by a recording checks again.
  final Duration recordingPoll;

  JobLock get _lock => JobLock(config.dataDir, procRoot: config.procRoot);

  RecordingFlag get _recording =>
      RecordingFlag(config.dataDir, procRoot: config.procRoot);

  List<_Candidate> _candidates() {
    final out = <_Candidate>[];
    final root = Directory(config.dataDir);
    if (!root.existsSync()) return out;
    final dirs = root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final d in dirs) {
      final meta = File(p.join(d.path, 'session.json'));
      if (!meta.existsSync()) continue;
      final m = readJsonObject(meta);
      if (m == null) {
        stderr.writeln('resume: skipping ${d.path}: session.json is damaged');
        continue;
      }
      final status = File(p.join(d.path, 'analysis', 'status.json'));
      // A session still recording has no duration yet; one whose recording
      // is gone and whose analysis never started has nothing to analyse.
      if (m['duration_s'] == null) continue;
      if (m.containsKey('error') && !status.existsSync()) continue;
      if (!status.existsSync() &&
          !File(p.join(d.path, 'recording.mkv')).existsSync()) {
        continue;
      }
      out.add(
        _Candidate(
          p.basename(d.path),
          status,
          () =>
              runSession?.call(d.path) ??
              AnalysisRunner(
                d.path,
                config,
                sys,
                client,
                recordingPoll: recordingPoll,
              ).run(),
        ),
      );
    }
    final games = Directory(p.join(config.dataDir, 'games'));
    if (games.existsSync()) {
      final slugs = games.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final g in slugs) {
        final slug = p.basename(g.path);
        final status = File(p.join(g.path, 'status.json'));
        // A finish job starts only when kuhy asks: a status, or his queued
        // request (`finish.json` state `queued`, written before any launch).
        final queued =
            readJsonObject(File(p.join(g.path, 'finish.json')))?['state'] ==
            'queued';
        if (!status.existsSync() && !queued) continue;
        out.add(
          _Candidate(
            'finish:$slug',
            status,
            () => FinishRunner(
              slug,
              config,
              sys,
              recordingPoll: recordingPoll,
            ).run(),
          ),
        );
      }
    }
    return out;
  }

  bool _due(AnalysisStatus? s) {
    if (s == null) return true;
    return switch (s.state) {
      StageState.idle || StageState.interrupted => true,
      StageState.running => true,
      StageState.waiting => (s.retryUnix ?? 0) <= sys.nowUnix(),
      StageState.done || StageState.failed => false,
    };
  }

  /// Rewrites every `running` status whose job no longer holds the lock to
  /// `interrupted` (its process died: shutdown, crash, kill). Returns the job
  /// ids changed.
  List<String> markInterrupted() {
    final live = _lock.holder()?.job;
    final changed = <String>[];
    for (final c in _candidates()) {
      final s = c.status;
      if (s == null || s.state != StageState.running || c.id == live) continue;
      final json = s.toJson()
        ..['state'] = StageState.interrupted.name
        ..['eta_s'] = null;
      writeAtomic(c.statusFile, jsonEncode(json));
      changed.add(c.id);
    }
    return changed;
  }

  /// Marks [c] `failed` with the reason [e], keeping its stage and tokens.
  void _markFailed(_Candidate c, Object e) {
    stderr.writeln('resume: ${c.id} crashed: $e');
    try {
      final s = c.status;
      writeAtomic(
        c.statusFile,
        jsonEncode(
          AnalysisStatus(
            stage: s?.stage ?? 0,
            done: s?.done ?? 0,
            total: s?.total ?? 0,
            state: StageState.failed,
            error: '$e',
            tokens: s?.tokens ?? Usage.zero,
            startedUnix: s?.startedUnix,
          ).toJson(),
        ),
      );
    } on Object catch (w) {
      stderr.writeln('resume: cannot record the failure of ${c.id}: $w');
    }
  }

  /// Applies retention, then runs every due job in turn. A job that throws
  /// is marked `failed` and the next one still runs. Exit code 0, or
  /// [JobExit.failed] when any job crashed (after all were tried).
  Future<int> run() async {
    try {
      applyRetention(config, sys.nowUnix());
    } on Object catch (e) {
      stderr.writeln('resume: retention failed: $e');
    }
    if (_recording.live || _lock.holder() != null) return JobExit.done;
    markInterrupted();
    final tried = <String>{};
    var crashed = false;
    while (!_recording.live) {
      final next = [
        for (final c in _candidates())
          if (!tried.contains(c.id) && _due(c.status)) c,
      ];
      if (next.isEmpty) break;
      tried.add(next.first.id);
      final int code;
      try {
        code = await next.first.launch();
      } on Object catch (e) {
        crashed = true;
        _markFailed(next.first, e);
        continue;
      }
      // Queued behind a job that appeared meanwhile: let it finish first.
      if (code == JobExit.waiting && _lock.holder() != null) break;
    }
    return crashed ? JobExit.failed : JobExit.done;
  }
}
