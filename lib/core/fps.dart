/// MangoHud frame-time logs and the figures kept per session.
///
/// MangoHud 0.8.x writes one CSV per game run: an `os,cpu,...` pair of
/// lines, then a header starting `fps,frametime,...,elapsed`, then one row
/// per frame (`frametime` in milliseconds, `elapsed` in nanoseconds since
/// the log started). `log_versioning` adds a preamble; columns are found by
/// header name, so extra or reordered ones do not matter.
library;

/// The frames of one MangoHud log.
class FpsLog {
  const new _(this.frametimesMs, this.elapsedNs);

  /// Parses [csv]; null when it has no frame-metrics header or no valid row.
  static FpsLog? parse(String csv) {
    final lines = csv.split('\n');
    final head = lines.indexWhere((l) => l.startsWith('fps,'));
    if (head < 0) return null;
    final cols = lines[head].trim().split(',');
    final ft = cols.indexOf('frametime');
    final el = cols.indexOf('elapsed');
    if (ft < 0 || el < 0) return null;
    final frames = <double>[];
    final elapsed = <int>[];
    for (final line in lines.skip(head + 1)) {
      final cells = line.trim().split(',');
      if (cells.length != cols.length) continue;
      final f = double.tryParse(cells[ft]);
      final e = int.tryParse(cells[el]);
      if (f == null || e == null || f <= 0) continue;
      frames.add(f);
      elapsed.add(e);
    }
    return frames.isEmpty ? null : FpsLog._(frames, elapsed);
  }

  /// Frame times, milliseconds.
  final List<double> frametimesMs;

  /// Time of each frame since the log started, nanoseconds.
  final List<int> elapsedNs;

  /// Length of the log, seconds.
  double get durationS => elapsedNs.last / 1e9;

  /// Whether the log (it ends at [fileEndUnix], its last write) overlaps
  /// the span [from]..[to], unix seconds.
  bool overlaps({
    required double fileEndUnix,
    required double from,
    required double to,
  }) => fileEndUnix - durationS < to && fileEndUnix > from;

  /// The frame times of the frames that fall in [from]..[to].
  List<double> frametimesBetween({
    required double fileEndUnix,
    required double from,
    required double to,
  }) {
    final start = fileEndUnix - durationS;
    return [
      for (var i = 0; i < frametimesMs.length; i++)
        if (start + elapsedNs[i] / 1e9 >= from &&
            start + elapsedNs[i] / 1e9 <= to)
          frametimesMs[i],
    ];
  }
}

/// What `session.json` keeps: `fps: {avg, p1_low, min, samples}`.
class FpsStats {
  /// Creates the figures.
  const new(this.avg, this.p1Low, this.min, this.samples);

  /// Frames per second over the whole span (frames / total frame time).
  final double avg;

  /// 1% low: the rate of the frame time that 99% of the frames beat.
  final double p1Low;

  /// The slowest frame's rate.
  final double min;

  /// Frames counted.
  final int samples;

  /// The `session.json` form.
  Map<String, Object?> toJson() => {
    'avg': avg,
    'p1_low': p1Low,
    'min': min,
    'samples': samples,
  };
}

double _round1(double v) => (v * 10).round() / 10;

/// Figures of [frametimesMs]; null when there are none.
FpsStats? fpsStats(List<double> frametimesMs) {
  if (frametimesMs.isEmpty) return null;
  final n = frametimesMs.length;
  final sorted = [...frametimesMs]..sort();
  final total = sorted.fold<double>(0, (a, b) => a + b);
  final p99 = sorted[(n * 99 + 99) ~/ 100 - 1]; // nearest rank
  return FpsStats(
    _round1(n * 1000 / total),
    _round1(1000 / p99),
    _round1(1000 / sorted.last),
    n,
  );
}
