/// What the marker stills and the pasted note lines look like. Pure Dart: the
/// wrapper, the analyzer and the web page all import it, so the file name a
/// still gets and the emoji a line starts with are defined once.
library;

import 'package:game_research/core/markers.dart';

/// Stage 1 cuts `m_NN_<tag>.mkv` per marker; the still shares the stem.
/// [i] is the 1-based position in `parseMarkers` order, 2 digits at least.
String stillName(int i, MarkerTag tag) =>
    'm_${i.toString().padLeft(2, '0')}_${tag.name}.jpg';

/// ffmpeg arguments (after the program name) that write the full-resolution
/// frame at [offsetS] of [video] to [out] as JPEG quality 2 (`-q:v 2`).
/// The seek is absolute (`-seek_timestamp`): the recording's first frame sits
/// at the recorder start-up delay, not at 0 (see `Stage1`).
List<String> stillArgv(String video, double offsetS, String out) => [
  '-hide_banner',
  '-nostdin',
  '-v',
  'error',
  '-seek_timestamp',
  '1',
  '-ss',
  offsetS.toStringAsFixed(3),
  '-i',
  video,
  '-frames:v',
  '1',
  '-q:v',
  '2',
  '-y',
  out,
];

/// `h:mm:ss` of [s] seconds (floored, never negative).
String hms(double s) {
  final total = s < 0 ? 0 : s.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final sec = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '$h:${two(m)}:${two(sec)}';
}

/// The emoji that opens a note line.
String tagEmoji(MarkerTag tag) => switch (tag) {
  MarkerTag.good => '👍',
  MarkerTag.bad => '👎',
  MarkerTag.confusing => '❓',
  MarkerTag.note => '📝',
};
