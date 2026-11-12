import 'package:flutter_test/flutter_test.dart';

import 'fake_wrapper.dart';
import 'notes_fixtures.dart';
import 'reader_fixtures.dart';

Finder label(String l) => find.bySemanticsLabel(RegExp('^${RegExp.escape(l)}'));

void main() {
  setUpAll(loadInter);

  testWidgets('files copy stays off until every still of it is cut', (t) async {
    final parts = twoParts();
    ((parts.first['markers']! as List).first as Map)['still'] = false;
    final w = FakeWrapper()..noteParts = parts;
    await openNotes(t, w);
    await t.tap(label('copy notes 1 files'), warnIfMissed: false);
    await t.tap(label('copy notes 2 files'));
    await t.pump();
    await t.pump();
    expect(w.calls.where((c) => c.startsWith('POST')), [
      'POST /api/games/1/notes/2/copy?what=files',
    ]);
    await t.pump(const Duration(seconds: 2));
    await endNotes(t);
  });
}
