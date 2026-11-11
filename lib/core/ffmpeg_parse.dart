/// Parsers for what ffmpeg and ffprobe print in stage 1.
library;

import 'dart:convert';

final _ptsTime = RegExp(r'Parsed_showinfo.*\bpts_time:\s*([0-9.]+)');
final _freezeStart = RegExp(r'freezedetect\.freeze_start:\s*([0-9.]+)');
final _freezeEnd = RegExp(r'freezedetect\.freeze_end:\s*([0-9.]+)');

/// Scene-cut times from a `select='gt(scene,X)',showinfo` run's stderr.
List<double> parseSceneCuts(String log) => [
  for (final m in _ptsTime.allMatches(log)) double.parse(m[1]!),
];

/// A stretch with no motion.
class Span {
  /// Creates a span from [start] to [end] seconds.
  const new(this.start, this.end);

  /// Start, seconds.
  final double start;

  /// End, seconds.
  final double end;

  /// Length, seconds.
  double get length => end - start;

  /// One `still.jsonl` object.
  Map<String, Object?> toJson() => {'start_s': start, 'end_s': end};
}

/// Freeze spans from a `freezedetect` run's stderr. A freeze still open at
/// the end of the file ends at [durationS]; an end with no start is noise.
List<Span> parseFreezes(String log, {required double durationS}) {
  final spans = <Span>[];
  double? open;
  for (final line in const LineSplitter().convert(log)) {
    final start = _freezeStart.firstMatch(line);
    if (start != null) {
      open = double.parse(start[1]!);
      continue;
    }
    final end = _freezeEnd.firstMatch(line);
    if (end != null && open != null) {
      spans.add(Span(open, double.parse(end[1]!)));
      open = null;
    }
  }
  if (open != null) spans.add(Span(open, durationS));
  return spans;
}

Map<String, Object?> _object(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException {
    // falls through to the shared error below
  }
  throw FormatException('ffprobe output is not a JSON object: $json');
}

/// `format.duration` from `ffprobe -show_entries format=duration -of json`.
double parseDuration(String json) {
  final format = _object(json)['format'];
  final raw = format is Map ? format['duration'] : null;
  final value = double.tryParse('${raw ?? ''}');
  if (value == null) throw FormatException('no duration in: $json');
  return value;
}

/// One chapter as ffprobe reports it.
class ProbedChapter {
  /// Creates a chapter starting at [start] seconds.
  const new(this.start, this.title);

  /// Start, seconds.
  final double start;

  /// Title tag ('' when absent).
  final String title;
}

/// Chapters from `ffprobe -show_chapters -of json`.
List<ProbedChapter> parseChapters(String json) {
  final list = _object(json)['chapters'];
  if (list is! List) return const [];
  return [
    for (final c in list.cast<Map<String, Object?>>())
      ProbedChapter(
        double.parse('${c['start_time']}'),
        ((c['tags'] as Map?)?['title'] as String?) ?? '',
      ),
  ];
}
