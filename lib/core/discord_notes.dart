/// kuhy's own marker notes of one game, cut into Discord-sized parts.
///
/// Only text kuhy typed ends up here (never model output). A part is one
/// message: at most [kMaxMarkers] marker lines and under [kMaxChars]
/// characters (Discord's limit is 2000; UTF-16 units over-count emoji, which
/// errs on the safe side).
library;

import 'package:game_research/core/markers.dart';
import 'package:game_research/core/share_contract.dart';

/// Marker lines per part.
const kMaxMarkers = 10;

/// Exclusive upper bound of a part's text length.
const kMaxChars = 2000;

/// One session's markers, with the local start time that names its date.
class NoteSession {
  /// Creates the input of one session.
  const new({required this.id, required this.started, required this.markers});

  /// Session folder name.
  final String id;

  /// Local start time.
  final DateTime started;

  /// Markers in `parseMarkers` order.
  final List<Marker> markers;
}

/// One marker line of a part.
class NoteLine {
  /// Creates a line.
  const new({
    required this.session,
    required this.i,
    required this.tag,
    required this.time,
    required this.note,
    required this.line,
  });

  /// Session folder name.
  final String session;

  /// 1-based marker number in its session (the clip / still number).
  final int i;

  /// Tag.
  final MarkerTag tag;

  /// `h:mm:ss`.
  final String time;

  /// The note, one line.
  final String note;

  /// The text line pasted into Discord.
  final String line;
}

/// One message.
class NotePart {
  /// Creates a part.
  const new({
    required this.n,
    required this.of,
    required this.text,
    required this.markers,
  });

  /// 1-based number.
  final int n;

  /// How many parts there are.
  final int of;

  /// The message text.
  final String text;

  /// The marker lines in it.
  final List<NoteLine> markers;
}

String _two(int v) => v.toString().padLeft(2, '0');

String _dateLine(DateTime d) => '__${d.year}-${_two(d.month)}-${_two(d.day)}__';

String _oneLine(String note) => note.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ');

// Longest header, `**<name>** · my notes 999/999`, for the first packing pass
// (the real `of` is known only after packing and is never longer).
String _header(String game, String counter) => '**$game** · my notes $counter';

/// The parts for [game], sessions oldest first. A session without markers is
/// skipped; no markers at all gives no parts. A note too long for one message
/// is cut with an ellipsis.
List<NotePart> buildParts(String game, List<NoteSession> sessions) {
  final ordered = [...sessions]..sort((a, b) => a.started.compareTo(b.started));
  final budget = kMaxChars - 1 - _header(game, '999/999').length;
  final groups = <List<(NoteSession, NoteLine)>>[[]];
  var used = 0;
  NoteSession? current;
  for (final s in ordered) {
    final dateCost = 1 + _dateLine(s.started).length;
    for (var k = 0; k < s.markers.length; k++) {
      final entry = _fit(_entry(s, k + 1, s.markers[k]), budget - dateCost - 1);
      final cost = 1 + entry.line.length;
      var newDate = groups.last.isEmpty || !identical(current, s);
      final full =
          groups.last.length >= kMaxMarkers ||
          used + cost + (newDate ? dateCost : 0) > budget;
      if (groups.last.isNotEmpty && full) {
        groups.add([]);
        used = 0;
        newDate = true;
      }
      if (newDate) used += dateCost;
      groups.last.add((s, entry));
      used += cost;
      current = s;
    }
  }
  final filled = groups.where((g) => g.isNotEmpty).toList();
  return [
    for (var n = 0; n < filled.length; n++)
      _part(game, n + 1, filled.length, filled[n]),
  ];
}

NoteLine _entry(NoteSession s, int i, Marker m) {
  final note = _oneLine(m.note.trim());
  final time = hms(m.offsetS);
  final head = '${tagEmoji(m.tag)} `$time`';
  return NoteLine(
    session: s.id,
    i: i,
    tag: m.tag,
    time: time,
    note: note,
    line: note.isEmpty ? head : '$head $note',
  );
}

// [e] with its note cut so the line is at most [max] characters.
NoteLine _fit(NoteLine e, int max) {
  if (e.line.length <= max) return e;
  final head = e.line.substring(0, e.line.length - e.note.length);
  final note = '${e.note.substring(0, max - head.length - 1)}…';
  return NoteLine(
    session: e.session,
    i: e.i,
    tag: e.tag,
    time: e.time,
    note: note,
    line: '$head$note',
  );
}

NotePart _part(
  String game,
  int n,
  int of,
  List<(NoteSession, NoteLine)> entries,
) {
  final lines = [_header(game, '$n/$of')];
  NoteSession? last;
  for (final (s, e) in entries) {
    if (!identical(last, s)) lines.add(_dateLine(s.started));
    lines.add(e.line);
    last = s;
  }
  return NotePart(
    n: n,
    of: of,
    text: lines.join('\n'),
    markers: [for (final (_, e) in entries) e],
  );
}
