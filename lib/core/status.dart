/// `analysis/status.json`: what the GUI's progress ring shows.
library;

import 'package:game_research/core/usage.dart';

/// Where the analysis job is.
enum StageState {
  /// Never started.
  idle,

  /// A stage is running.
  running,

  /// Held back, retried later: queued behind another job, or the model's
  /// usage limit is reached. [AnalysisStatus.error] says which.
  waiting,

  /// The job's process died (shutdown, crash); `--resume-all` relaunches it.
  interrupted,

  /// All three stages finished.
  done,

  /// A stage failed; [AnalysisStatus.error] says why. Never retried by
  /// itself: a bad answer would cost a model call every retry.
  failed,
}

/// The job's progress.
class AnalysisStatus {
  /// Creates a status at [stage] (1-3), [done] of [total] items.
  const new({
    required this.stage,
    required this.done,
    required this.total,
    required this.state,
    this.error,
    this.tokens = Usage.zero,
    this.etaS,
    this.startedUnix,
    this.retryUnix,
  });

  /// Nothing has run yet.
  const new idle()
    : stage = 0,
      done = 0,
      total = 0,
      state = StageState.idle,
      error = null,
      tokens = Usage.zero,
      etaS = null,
      startedUnix = null,
      retryUnix = null;

  /// Reads `status.json`; an unknown state reads as idle.
  factory fromJson(Map<String, Object?> json) => AnalysisStatus(
    stage: (json['stage'] as num?)?.toInt() ?? 0,
    done: (json['done'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    state: StageState.values.asNameMap()[json['state']] ?? StageState.idle,
    error: json['error'] as String?,
    tokens: Usage.fromJson({
      ...?(json['tokens'] as Map?)?.cast<String, Object?>(),
      'cost_usd': json['cost_usd'],
    }),
    etaS: (json['eta_s'] as num?)?.toDouble(),
    startedUnix: (json['started_unix'] as num?)?.toDouble(),
    retryUnix: (json['retry_unix'] as num?)?.toDouble(),
  );

  /// Stage 1-3 (0 before the first).
  final int stage;

  /// Items done in this stage.
  final int done;

  /// Items in this stage.
  final int total;

  /// Overall state.
  final StageState state;

  /// Why it failed or waits.
  final String? error;

  /// Tokens and cost of every model call so far.
  final Usage tokens;

  /// Seconds the current stage still needs; null when unknown.
  final double? etaS;

  /// When the job started, unix seconds.
  final double? startedUnix;

  /// A waiting job is not retried before this unix second.
  final double? retryUnix;

  /// 0..1 over all three stages, each a third.
  double get progress {
    if (state == StageState.done) return 1;
    if (stage <= 0) return 0;
    final within = total > 0 ? done / total : 0.0;
    return ((stage - 1) + within) / 3;
  }

  /// The `status.json` object.
  Map<String, Object?> toJson() => {
    'stage': stage,
    'done': done,
    'total': total,
    'state': state.name,
    'progress': progress,
    'tokens': tokens.tokens,
    'cost_usd': tokens.costUsd,
    'eta_s': etaS,
    'started_unix': startedUnix,
    if (retryUnix != null) 'retry_unix': retryUnix,
    if (error != null) 'error': error,
  };
}

/// Seconds a stage still needs, from the first progress report it saw.
///
/// The first report (`done` at `nowUnix`) is the baseline, so a stage that
/// resumes with half its items already done does not look fast. Null until
/// one item completed after the baseline.
class StageClock {
  /// A clock for a stage that has not reported yet.
  new();

  double? _t0;
  int _d0 = 0;

  /// Feeds a report; returns the ETA, null when unknown.
  double? eta(double nowUnix, int done, int total) {
    final t0 = _t0;
    if (t0 == null) {
      _t0 = nowUnix;
      _d0 = done;
      return null;
    }
    final gained = done - _d0;
    if (gained <= 0 || nowUnix <= t0) return null;
    return (nowUnix - t0) * (total - done) / gained;
  }
}
