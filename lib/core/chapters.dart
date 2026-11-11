/// Markers as Matroska chapters, in ffmpeg's FFMETADATA format.
///
/// Each marker opens a chapter that runs to the next marker or the end of
/// the file, so a player's chapter list is the marker list. The file is
/// remuxed with `-map_chapters` (streams copied, `recorder_args.dart`).
library;

import 'package:game_research/core/markers.dart';

/// Escapes FFMETADATA specials (`=`, `;`, `#`, `\`, newline) with `\`.
String escapeMetadata(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (const ['=', ';', '#', r'\', '\n'].contains(char)) out.write(r'\');
    out.write(char);
  }
  return out.toString();
}

/// The FFMETADATA text for [markers] on a file [durationS] long.
///
/// Times are milliseconds. A marker at or past the end still gets a 1 ms
/// chapter, and two markers at the same instant do not produce an empty
/// chapter: each start is at least 1 ms after the previous one.
String chaptersFfmetadata(List<Marker> markers, double durationS) {
  final sorted = [...markers]..sort((a, b) => a.offsetS.compareTo(b.offsetS));
  final endMs = (durationS * 1000).round();
  final starts = <int>[];
  for (final m in sorted) {
    var start = (m.offsetS * 1000).round();
    if (start > endMs) start = endMs;
    if (starts.isNotEmpty && start <= starts.last) start = starts.last + 1;
    starts.add(start);
  }
  final out = StringBuffer(';FFMETADATA1\n');
  for (var i = 0; i < sorted.length; i++) {
    final start = starts[i];
    final next = i + 1 < starts.length ? starts[i + 1] : endMs;
    final end = next > start ? next : start + 1;
    out
      ..write('[CHAPTER]\nTIMEBASE=1/1000\n')
      ..write('START=$start\nEND=$end\n')
      ..write('title=${escapeMetadata(sorted[i].label)}\n');
  }
  return out.toString();
}
