/// kuhy's marker notes of a game as `GET /api/games/<appid>/notes` serves
/// them: message parts, each with its marker lines.
library;

/// One marker line of a part.
class NoteMarker {
  /// Creates a marker.
  const new({
    required this.session,
    required this.i,
    required this.tag,
    required this.time,
    required this.note,
    required this.still,
  });

  /// Parses one entry of a part's `markers`.
  factory fromJson(Map<String, Object?> j) => NoteMarker(
    session: '${j['session'] ?? ''}',
    i: (j['i'] as num?)?.toInt() ?? 0,
    tag: '${j['tag'] ?? ''}',
    time: '${j['time'] ?? ''}',
    note: '${j['note'] ?? ''}',
    still: j['still'] == true,
  );

  /// Session folder name (`YYYYMMDD-HHMMSS-slug`).
  final String session;

  /// 1-based marker number in its session.
  final int i;

  /// Tag name (`good`, ...).
  final String tag;

  /// `h:mm:ss`.
  final String time;

  /// The note kuhy typed (may be empty).
  final String note;

  /// The still frame is cut and can be fetched.
  final bool still;

  /// `YYYY-MM-DD` of the session's start (the date header of the part text).
  String get date {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})-').firstMatch(session);
    return m == null ? session : '${m[1]}-${m[2]}-${m[3]}';
  }
}

/// One Discord message of notes.
class NotePart {
  /// Creates a part.
  const new({required this.n, required this.of, required this.markers});

  /// Parses one entry of `parts`.
  factory fromJson(Map<String, Object?> j) => NotePart(
    n: (j['n'] as num?)?.toInt() ?? 0,
    of: (j['of'] as num?)?.toInt() ?? 0,
    markers: [
      for (final m in (j['markers'] as List?) ?? const [])
        NoteMarker.fromJson(m as Map<String, Object?>),
    ],
  );

  /// 1-based number.
  final int n;

  /// Number of parts.
  final int of;

  /// The marker lines in it.
  final List<NoteMarker> markers;

  /// Whether any still of the part exists (the files copy has something).
  bool get hasStills => markers.any((m) => m.still);
}

/// The doc behind `GET /api/doc`.
typedef DocText = ({String text, bool short});
