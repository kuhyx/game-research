/// A background job's progress as the page shows it: the analysis of one
/// session, or the per-game "research finished" merge. Every field of the
/// newer wrapper is optional so an old session still reads.
library;

num? _num(Object? v) => v is num ? v : null;

/// Token counters of a job.
class Tokens {
  /// Creates counters.
  const new({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
  });

  /// Parses `{in, out, cache_read, cache_write}`, or null when absent.
  static Tokens? fromJson(Object? j) {
    if (j is! Map) return null;
    int n(String k) => _num(j[k])?.toInt() ?? 0;
    return Tokens(
      input: n('in'),
      output: n('out'),
      cacheRead: n('cache_read'),
      cacheWrite: n('cache_write'),
    );
  }

  /// Fresh input tokens.
  final int input;

  /// Output tokens.
  final int output;

  /// Cache reads.
  final int cacheRead;

  /// Cache writes.
  final int cacheWrite;

  /// All four counters added.
  int get total => input + output + cacheRead + cacheWrite;
}

/// Progress of one job.
class JobStatus {
  /// Creates a status.
  const new({
    this.state = 'idle',
    this.stage = 0,
    this.done = 0,
    this.total = 0,
    this.progress = 0,
    this.tokens,
    this.costUsd,
    this.etaS,
  });

  /// Parses a `status.json` view; null reads as idle.
  factory fromJson(Object? j) {
    if (j is! Map) return const JobStatus();
    return JobStatus(
      state: '${j['state'] ?? 'idle'}',
      stage: _num(j['stage'])?.toInt() ?? 0,
      done: _num(j['done'])?.toInt() ?? 0,
      total: _num(j['total'])?.toInt() ?? 0,
      progress: _num(j['progress'])?.toDouble() ?? 0,
      tokens: Tokens.fromJson(j['tokens']),
      costUsd: _num(j['cost_usd'])?.toDouble(),
      etaS: _num(j['eta_s'])?.toDouble(),
    );
  }

  /// idle | running | waiting | interrupted | done | failed.
  final String state;

  /// Stage 1-3 (0 before the first).
  final int stage;

  /// Items done in the stage.
  final int done;

  /// Items in the stage.
  final int total;

  /// 0..1 over the whole job.
  final double progress;

  /// Model tokens spent so far.
  final Tokens? tokens;

  /// Cost in USD when the models report it.
  final double? costUsd;

  /// Seconds left, null when unknown.
  final double? etaS;

  /// Whether the job works or waits for a retry.
  bool get active => state == 'running' || state == 'waiting';

  /// Whether `done/total` means something to read: stage 1 counts ffmpeg
  /// time in 1000 units (the ring carries it) and a one-call stage is 0/1.
  bool get showsItems => stage >= 2 && total > 1;

  /// Minutes left, rounded up; null when unknown or zero.
  int? get etaMin {
    final e = etaS;
    return e == null || e <= 0 ? null : (e / 60).ceil();
  }
}
