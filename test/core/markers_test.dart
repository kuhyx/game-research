import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/markers.dart';

void main() {
  group('markerOffset', () {
    test('is wall minus t0, rounded to the millisecond', () {
      expect(markerOffset(1000.12345, 990), closeTo(10.123, 1e-9));
    });

    test('never goes below zero (press before the first frame)', () {
      expect(markerOffset(989.5, 990), 0);
    });
  });

  group('MarkerTag', () {
    test('parses every tag by name and refuses an unknown one', () {
      for (final tag in MarkerTag.values) {
        expect(MarkerTag.parse(tag.name), tag);
      }
      expect(MarkerTag.tryParse('great'), isNull);
      expect(() => MarkerTag.parse('great'), throwsFormatException);
    });

    test('each tag has its own flash colour', () {
      final colours = {for (final t in MarkerTag.values) t.flashHex};
      expect(colours, hasLength(4));
      expect(MarkerTag.good.flashHex, startsWith('#'));
    });
  });

  group('Marker jsonl', () {
    final wall = DateTime.utc(2026, 11, 11, 12, 0, 5, 250);

    test('round-trips through a line', () {
      final m = Marker(
        wallUnix: wall.millisecondsSinceEpoch / 1000,
        offsetS: 5.25,
        tag: MarkerTag.note,
        note: 'door had no cue',
      );
      final back = Marker.fromJson(m.toJson());
      expect(back.offsetS, 5.25);
      expect(back.tag, MarkerTag.note);
      expect(back.note, 'door had no cue');
      expect(m.toJson()['wall'], '2026-11-11T12:00:05.250Z');
      expect(m.toLine(), isNot(contains('\n')));
    });

    test('parseMarkers skips blank lines and sorts by offset', () {
      const text =
          '{"wall_unix":3,"offset_s":3,"tag":"bad","note":""}\n\n'
          '{"wall_unix":1,"offset_s":1,"tag":"good","note":""}\n';
      final ms = parseMarkers(text);
      expect(ms.map((m) => m.tag), [MarkerTag.good, MarkerTag.bad]);
    });

    test('parseMarkers skips torn, junk and non-marker lines', () {
      final good = const Marker(
        wallUnix: 1,
        offsetS: 5,
        tag: MarkerTag.good,
      ).toLine();
      // A power cut leaves a half line and NULs after the last whole one.
      final text = '$good\n{"offset_s":1}\nnot json\n[1]\n{"wall_unix\x00\x00';
      expect(parseMarkers(text).map((m) => m.offsetS), [5]);
    });

    test('a missing note reads as empty', () {
      final m = Marker.fromJson(const {
        'wall_unix': 1,
        'offset_s': 1,
        'tag': 'good',
      });
      expect(m.note, '');
      expect(m.label, 'good');
      expect(m.copyWith(note: 'x').label, 'good: x');
    });
  });

  test('countByTag counts each tag, zero for absent ones', () {
    final ms = [
      const Marker(wallUnix: 1, offsetS: 1, tag: MarkerTag.good),
      const Marker(wallUnix: 2, offsetS: 2, tag: MarkerTag.good),
    ];
    expect(countByTag(ms), {
      MarkerTag.good: 2,
      MarkerTag.bad: 0,
      MarkerTag.confusing: 0,
      MarkerTag.note: 0,
    });
  });
}
