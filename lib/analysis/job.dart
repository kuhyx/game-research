/// What every analysis job shares: exit codes, the waiting error, the status
/// file with progress, tokens and ETA, and the token tally of a folder.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/analysis/job_lock.dart';
import 'package:game_research/core/safe_json.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/core/usage.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// Exit codes of the analyzer.
abstract final class JobExit {
  /// Done.
  static const done = 0;

  /// A stage failed (status says why); not retried by itself.
  static const failed = 1;

  /// Bad arguments.
  static const usage = 2;

  /// The same job is already running.
  static const running = 3;

  /// Waiting: queued behind another job, or a usage limit; retried later.
  static const waiting = 4;
}

/// How long a usage limit holds a job back before `--resume-all` retries.
const kRetryAfterS = 1800.0;

/// Thrown by a stage when the job must wait and be retried later.
class WaitingError implements Exception {
  /// Creates the error; [retryAfterS] is how long until the retry.
  const new(this.message, {this.retryAfterS = kRetryAfterS});

  /// Why the job waits.
  final String message;

  /// Seconds until a retry makes sense.
  final double retryAfterS;

  @override
  String toString() => message;
}

/// Reads `usage` of every `captions.jsonl` row and `tokens`/`cost_usd` of
/// `stage3.json` under session folder [dir]: what the session spent so far.
Usage sessionUsage(String dir) {
  var total = Usage.zero;
  // Torn rows and a damaged stage3.json count as nothing: this runs inside
  // the status writer, so it must never throw.
  final captions = File(p.join(dir, 'analysis', 'captions.jsonl'));
  for (final row in readJsonl(captions).rows) {
    total += Usage.fromJson(row['usage']);
  }
  final s = readJsonObject(File(p.join(dir, 'analysis', 'stage3.json')));
  if (s != null) {
    try {
      total += Usage.fromJson({
        ...?(s['tokens'] as Map?)?.cast<String, Object?>(),
        'cost_usd': s['cost_usd'],
      });
    } on Object {
      // junk token fields: nothing to add
    }
  }
  return total;
}

/// The stage a job is in, so a failure is reported against it.
class StageRef {
  /// Starts at stage [value].
  new([this.value = 1]);

  /// Current stage number.
  int value;
}

/// Runs [body] as job [job] under the machine-wide lock.
///
/// Busy machine: the same job already live is [JobExit.running]; any other
/// job live makes this one `waiting` ([JobExit.waiting]), to be started by the
/// next job to finish or the resume timer. A [WaitingError] from the body is
/// `waiting` with a retry time; any other error is `failed`. The body writes
/// the `done` status itself.
Future<int> runLocked({
  required String job,
  required Config config,
  required StatusWriter status,
  required Future<void> Function(StageRef stage) body,
  int? ownerPid,
}) async {
  final lock = JobLock(
    config.dataDir,
    procRoot: config.procRoot,
    selfPid: ownerPid,
  );
  if (!lock.acquire(job)) {
    final holder = lock.holder();
    if (holder?.job == job) return JobExit.running;
    status.write(
      0,
      0,
      1,
      StageState.waiting,
      error: 'queued behind ${holder?.job}',
    );
    return JobExit.waiting;
  }
  final stage = StageRef();
  try {
    await body(stage);
    return JobExit.done;
  } on WaitingError catch (e) {
    status.write(
      stage.value,
      0,
      1,
      StageState.waiting,
      error: '$e',
      retryAfterS: e.retryAfterS,
    );
    return JobExit.waiting;
  } on Object catch (e) {
    status.write(stage.value, 0, 1, StageState.failed, error: '$e');
    return JobExit.failed;
  } finally {
    lock.release();
  }
}

/// Writes a job's `status.json`.
class StatusWriter {
  /// Writes to [file]; [usage] says what has been spent so far.
  new(this.file, this.sys, this.usage) : startedUnix = sys.nowUnix();

  /// The status file.
  final File file;

  /// Clock seam.
  final Sys sys;

  /// The tokens spent so far.
  final Usage Function() usage;

  /// When this run started.
  final double startedUnix;

  int _stage = 0;
  int _done = 0;
  int _total = 0;
  StageClock _clock = StageClock();

  /// Writes one status; the ETA comes from the stage's own progress. A
  /// `waiting` status in the stage that last reported keeps that stage's
  /// done/total, so the ring does not fall back to the stage's start.
  void write(
    int stage,
    int done,
    int total,
    StageState state, {
    String? error,
    double? retryAfterS,
  }) {
    if (stage != _stage) {
      _stage = stage;
      _done = _total = 0;
      _clock = StageClock();
    }
    final held = state == StageState.waiting && _total > 0;
    if (!held) {
      _done = done;
      _total = total;
    }
    final now = sys.nowUnix();
    writeAtomic(
      file,
      jsonEncode(
        AnalysisStatus(
          stage: stage,
          done: _done,
          total: _total,
          state: state,
          error: error,
          tokens: usage(),
          etaS: state == StageState.running
              ? _clock.eta(now, done, total)
              : null,
          startedUnix: startedUnix,
          retryUnix: retryAfterS == null ? null : now + retryAfterS,
        ).toJson(),
      ),
    );
  }
}
