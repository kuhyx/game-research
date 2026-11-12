import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/discord_notes.dart';
import 'package:game_research/core/markers.dart';

Marker m(double off, MarkerTag tag, [String note = '']) =>
    Marker(wallUnix: 1.7e9 + off, offsetS: off, tag: tag, note: note);

NoteSession day(String id, DateTime start, List<Marker> markers) =>
    NoteSession(id: id, started: start, markers: markers);

void main() {
  final d1 = DateTime(2026, 11, 10, 20);
  final d2 = DateTime(2026, 11, 11, 21);

  test('one part: header, date line, one line per marker', () {
    final parts = buildParts('Librarian', [
      day('s1', d1, [
        m(65, MarkerTag.good, 'nice sort'),
        m(3700, MarkerTag.bad),
        m(3701, MarkerTag.confusing, 'why?'),
        m(3800, MarkerTag.note, 'idea'),
      ]),
    ]);
    expect(parts, hasLength(1));
    expect(
      parts.single.text,
      [
        '**Librarian** · my notes 1/1',
        '__2026-11-10__',
        '👍 `0:01:05` nice sort',
        '👎 `1:01:40`',
        '❓ `1:01:41` why?',
        '📝 `1:03:20` idea',
      ].join('\n'),
    );
    expect([parts.single.n, parts.single.of], [1, 1]);
  });

  test('an empty note leaves no trailing space', () {
    final line = buildParts('G', [
      day('s', d1, [m(5, MarkerTag.bad)]),
    ]).single.markers.single.line;
    expect(line, '👎 `0:00:05`');
    expect(line.endsWith(' '), isFalse);
  });

  test('marker entries carry session, 1-based index, tag, time, note', () {
    final e = buildParts('G', [
      day('s9', d1, [m(5, MarkerTag.bad), m(9, MarkerTag.note, 'x')]),
    ]).single.markers;
    expect(
      [for (final x in e) (x.session, x.i, x.tag, x.time, x.note)],
      [
        ('s9', 1, MarkerTag.bad, '0:00:05', ''),
        ('s9', 2, MarkerTag.note, '0:00:09', 'x'),
      ],
    );
  });

  test('sessions come oldest first whatever the input order', () {
    final parts = buildParts('G', [
      day('late', d2, [m(1, MarkerTag.good, 'second')]),
      day('early', d1, [m(1, MarkerTag.good, 'first')]),
    ]);
    final text = parts.single.text;
    expect(text.indexOf('2026-11-10'), lessThan(text.indexOf('2026-11-11')));
    expect(text.indexOf('first'), lessThan(text.indexOf('second')));
    expect(parts.single.markers.map((e) => e.session), ['early', 'late']);
  });

  test('a session without markers adds no date line; none = no parts', () {
    expect(buildParts('G', [day('s', d1, const [])]), isEmpty);
    expect(buildParts('G', const []), isEmpty);
    final parts = buildParts('G', [
      day('a', d1, const []),
      day('b', d2, [m(1, MarkerTag.good)]),
    ]);
    expect(parts.single.text.contains('2026-11-10'), isFalse);
  });

  test('splits at 10 markers; the date repeats in the next part', () {
    final parts = buildParts('G', [
      day('s', d1, [for (var i = 0; i < 25; i++) m(i * 1.0, MarkerTag.good)]),
    ]);
    expect(parts.map((p) => p.markers.length), [10, 10, 5]);
    expect([for (final p in parts) '${p.n}/${p.of}'], ['1/3', '2/3', '3/3']);
    for (final p in parts) {
      expect(p.text, contains('__2026-11-10__'));
      expect(p.text, contains('my notes ${p.n}/3'));
    }
    expect(parts[1].markers.first.i, 11);
  });

  test('a new session in a part gets its own date line', () {
    final parts = buildParts('G', [
      day('a', d1, [for (var i = 0; i < 8; i++) m(i * 1.0, MarkerTag.good)]),
      day('b', d2, [for (var i = 0; i < 4; i++) m(i * 1.0, MarkerTag.bad)]),
    ]);
    expect(parts.map((p) => p.markers.length), [10, 2]);
    expect(parts[0].text, contains('__2026-11-11__'));
    // Session b continues into part 2: the date comes again.
    expect(parts[1].text, contains('__2026-11-11__'));
    expect(parts[1].text.contains('__2026-11-10__'), isFalse);
  });

  test('splits at 2000 chars: every part stays under', () {
    final long = 'x' * 300;
    final parts = buildParts('Long Game', [
      day('s', d1, [
        for (var i = 0; i < 9; i++) m(i * 1.0, MarkerTag.note, long),
      ]),
    ]);
    expect(parts.length, greaterThan(1));
    for (final p in parts) {
      expect(p.text.length, lessThan(2000));
      expect(p.markers.length, lessThanOrEqualTo(10));
    }
    expect(parts.expand((p) => p.markers), hasLength(9));
  });

  test('one note longer than a message is cut with an ellipsis', () {
    final parts = buildParts('G', [
      day('s', d1, [m(1, MarkerTag.note, 'y' * 5000), m(2, MarkerTag.good)]),
    ]);
    for (final p in parts) {
      expect(p.text.length, lessThan(2000));
    }
    final line = parts.first.markers.first.line;
    expect(line.endsWith('…'), isTrue);
    expect(parts.expand((p) => p.markers), hasLength(2));
  });

  test('line breaks inside a note collapse to a space', () {
    final e = buildParts('G', [
      day('s', d1, [m(1, MarkerTag.note, 'a\n  b\r\nc')]),
    ]).single.markers.single;
    expect(e.note, 'a b c');
  });
}
