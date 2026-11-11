/// Markers kuhy drops while playing, and their `markers.jsonl` lines.
///
/// One line per marker: wall time (ISO and unix), offset in seconds on the
/// recording's timeline, tag and an optional one-line note. The recording's
/// timeline starts at the session's t0 (a unix time, `recorder_args.dart`),
/// so an offset is simply the press time minus t0.
library;

import 'dart:convert';

/// The four marker kinds, with the colour their border flash uses.
enum MarkerTag {
  /// Something the game does well.
  good('#3cb043'),

  /// Something the game does badly.
  bad('#e2302f'),

  /// A moment kuhy did not understand.
  confusing('#f0c020'),

  /// A free note (one line, optional).
  note('#2f6fe2');

  new(this.flashHex);

  /// Border flash colour, `#rrggbb` (kuhy's choice: green, red, yellow,
  /// blue). Saturated on purpose: it must read over any game picture.
  final String flashHex;

  /// The tag named [name], or null.
  static MarkerTag? tryParse(String? name) {
    for (final tag in values) {
      if (tag.name == name) return tag;
    }
    return null;
  }

  /// The tag named [name]; a [FormatException] for anything else.
  static MarkerTag parse(String? name) =>
      tryParse(name) ?? (throw FormatException('unknown marker tag: $name'));
}

/// Seconds from [t0Unix] to [wallUnix], to the millisecond, never negative.
double markerOffset(double wallUnix, double t0Unix) {
  final offset = wallUnix - t0Unix;
  if (offset <= 0) return 0;
  return (offset * 1000).round() / 1000;
}

/// One marker.
class Marker {
  /// Creates a marker pressed at [wallUnix], [offsetS] into the recording.
  const new({
    required this.wallUnix,
    required this.offsetS,
    required this.tag,
    this.note = '',
  });

  /// Reads one decoded `markers.jsonl` object; throws on a missing field.
  factory fromJson(Map<String, Object?> json) {
    final wall = json['wall_unix'];
    final offset = json['offset_s'];
    if (wall is! num || offset is! num) {
      throw const FormatException('marker needs wall_unix and offset_s');
    }
    return Marker(
      wallUnix: wall.toDouble(),
      offsetS: offset.toDouble(),
      tag: MarkerTag.parse(json['tag'] as String?),
      note: json['note'] as String? ?? '',
    );
  }

  /// Unix time of the press, seconds.
  final double wallUnix;

  /// Seconds into the recording.
  final double offsetS;

  /// Which kind.
  final MarkerTag tag;

  /// The note ('' for none).
  final String note;

  /// Chapter title: the tag, plus the note when there is one.
  String get label => note.isEmpty ? tag.name : '${tag.name}: $note';

  /// A copy with [note] replaced.
  Marker copyWith({required String note}) =>
      Marker(wallUnix: wallUnix, offsetS: offsetS, tag: tag, note: note);

  /// The JSON object of one line.
  Map<String, Object?> toJson() => {
    'wall': DateTime.fromMillisecondsSinceEpoch(
      (wallUnix * 1000).round(),
      isUtc: true,
    ).toIso8601String(),
    'wall_unix': wallUnix,
    'offset_s': offsetS,
    'tag': tag.name,
    'note': note,
  };

  /// One `markers.jsonl` line, without the newline.
  String toLine() => jsonEncode(toJson());
}

/// Every marker in a `markers.jsonl` text, sorted by offset. A line that is
/// not a valid marker throws: a half-read marker file must not look complete.
List<Marker> parseMarkers(String text) {
  final markers = <Marker>[];
  for (final line in const LineSplitter().convert(text)) {
    if (line.trim().isEmpty) continue;
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('marker line is not an object: $line');
    }
    markers.add(Marker.fromJson(decoded));
  }
  return markers..sort((a, b) => a.offsetS.compareTo(b.offsetS));
}

/// How many markers of each tag, every tag present.
Map<MarkerTag, int> countByTag(Iterable<Marker> markers) {
  final counts = {for (final t in MarkerTag.values) t: 0};
  for (final m in markers) {
    counts[m.tag] = counts[m.tag]! + 1;
  }
  return counts;
}
