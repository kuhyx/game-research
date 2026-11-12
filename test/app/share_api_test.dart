import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/notes_models.dart';

import 'fake_wrapper.dart';
import 'notes_fixtures.dart';

void main() {
  group('share api', () {
    test('notes, copies and the still url', () async {
      final w = FakeWrapper()..noteParts = twoParts();
      final api = w.api();
      final parts = await api.notes(1);
      expect(parts.length, 2);
      expect(parts.first.markers.first.date, '2026-11-10');
      expect(parts.first.hasStills, isTrue);
      expect(
        const NoteMarker(
          session: 'odd',
          i: 1,
          tag: 'good',
          time: '',
          note: '',
          still: false,
        ).date,
        'odd',
      );
      expect(NotePart.fromJson(const {}).markers, isEmpty);
      await api.copyPart(1, 2, 'text');
      await api.copyMarker(stampA, 3);
      await api.copyDoc('/t/a.md');
      expect(w.calls.skip(1), [
        'POST /api/games/1/notes/2/copy?what=text',
        'POST /api/sessions/$stampA/markers/3/copy',
        'POST /api/doc/copy?path=%2Ft%2Fa.md',
      ]);
      expect(
        api.stillUrl(stampA, 3),
        'http://127.0.0.1:1/api/sessions/$stampA/still/3',
      );
      w.postStatus = 409;
      await expectLater(api.copyDoc('/t/a.md'), throwsA(isA<ApiError>()));
    });
  });
}
