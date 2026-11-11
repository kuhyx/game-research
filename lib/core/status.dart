/// `analysis/status.json`: what the GUI's progress ring shows.
library;

/// Where the analysis job is.
enum StageState {
  /// Never started.
  idle,

  /// A stage is running.
  running,

  /// All three stages finished.
  done,

  /// A stage failed; [AnalysisStatus.error] says why.
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
  });

  /// Nothing has run yet.
  const new idle()
    : stage = 0,
      done = 0,
      total = 0,
      state = StageState.idle,
      error = null;

  /// Reads `status.json`; an unknown state reads as idle.
  factory fromJson(Map<String, Object?> json) => AnalysisStatus(
    stage: (json['stage'] as num?)?.toInt() ?? 0,
    done: (json['done'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    state: StageState.values.asNameMap()[json['state']] ?? StageState.idle,
    error: json['error'] as String?,
  );

  /// Stage 1-3 (0 before the first).
  final int stage;

  /// Items done in this stage.
  final int done;

  /// Items in this stage.
  final int total;

  /// Overall state.
  final StageState state;

  /// Why it failed.
  final String? error;

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
    if (error != null) 'error': error,
  };
}
