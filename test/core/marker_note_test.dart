import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/markers.dart';

String _line(double offset, String tag, [String note = '']) => jsonEncode({
  'wall_unix': offset + 100,
  'offset_s': offset,
  'tag': tag,
  'note': note,
  'extra': 'kept',
});

void main() {
  // File order differs from offset order; one torn line sits between.
  final text =
      '${_line(30, 'bad')}\n'
      '{"wall_unix": 1, "offs\n'
      '${_line(10, 'good', 'old')}\n'
      '${_line(20, 'note')}\n';

  test('withMarkerNote edits marker i of the sorted order only', () {
    final out = withMarkerNote(text, 2, 'new note')!;
    final lines = out.trimRight().split('\n');
    expect(lines, hasLength(4));
    expect(lines[0], _line(30, 'bad'));
    expect(lines[1], '{"wall_unix": 1, "offs', reason: 'torn line untouched');
    expect(lines[2], _line(10, 'good', 'old'));
    expect(jsonDecode(lines[3]), containsPair('note', 'new note'));
    expect(jsonDecode(lines[3]), containsPair('extra', 'kept'));
    expect(parseMarkers(out).map((m) => m.note), ['old', 'new note', '']);
  });

  test('marker 1 and 3 land on the right lines', () {
    expect(parseMarkers(withMarkerNote(text, 1, 'a')!).map((m) => m.note), [
      'a',
      '',
      '',
    ]);
    expect(parseMarkers(withMarkerNote(text, 3, 'c')!).map((m) => m.note), [
      'old',
      '',
      'c',
    ]);
  });

  test('null for a marker that does not exist', () {
    expect(withMarkerNote(text, 0, 'x'), isNull);
    expect(withMarkerNote(text, 4, 'x'), isNull);
    expect(withMarkerNote('', 1, 'x'), isNull);
  });

  test('equal offsets keep file order, so index and edit agree', () {
    final same = [for (var k = 0; k < 40; k++) _line(5, 'good', 'n$k')]
        .join('\n');
    expect(parseMarkers(same).map((m) => m.note), [
      for (var k = 0; k < 40; k++) 'n$k',
    ]);
    final out = withMarkerNote(same, 37, 'edited')!;
    expect(out.split('\n')[36], contains('edited'));
  });
}
