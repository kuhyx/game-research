import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_wrapper.dart';
import 'notes_fixtures.dart';
import 'reader_fixtures.dart';

Finder label(String l) => find.bySemanticsLabel(RegExp('^${RegExp.escape(l)}'));

Finder field(String stamp, int i) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == 'note text $stamp $i',
);

Future<void> settleSave(WidgetTester t) async {
  for (var k = 0; k < 4; k++) {
    await t.pump();
  }
}

void main() {
  setUpAll(loadInter);

  testWidgets('a marker without a note shows a field and blocks its copies', (
    t,
  ) async {
    final w = FakeWrapper()..noteParts = twoParts(noted: false);
    await openNotes(t, w);
    expect(field(stampA, 2), findsOneWidget);
    expect(
      find.byType(TextField),
      findsOneWidget,
      reason: 'only the empty one',
    );
    for (final l in [
      'copy notes 1 files',
      'copy notes 1 text',
      'copy marker $stampA 2',
    ]) {
      await t.tap(label(l), warnIfMissed: false);
    }
    await t.tap(label('copy notes 2 files'));
    await t.pump();
    await t.pump();
    expect(w.calls.where((c) => c.startsWith('POST')), [
      'POST /api/games/1/notes/2/copy?what=files',
    ]);
    await t.pump(const Duration(seconds: 2));
    await endNotes(t);
  });

  testWidgets('Enter saves the note, the view re-reads and unlocks', (t) async {
    final w = FakeWrapper()..noteParts = twoParts(noted: false);
    await openNotes(t, w);
    await t.enterText(find.byType(TextField), '  fix the tooltip ');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settleSave(t);
    expect(w.calls.where((c) => c.contains('/markers/')), [
      'POST /api/sessions/$stampA/markers/2/note {"note":"fix the tooltip"}',
    ]);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('fix the tooltip'), findsOneWidget);
    await t.tap(label('copy notes 1 files'));
    await t.pump();
    await t.pump();
    expect(w.calls.last, 'POST /api/games/1/notes/1/copy?what=files');
    await t.pump(const Duration(seconds: 2));
    await endNotes(t);
  });

  testWidgets('a blank line saves nothing, a refusal shows the error', (
    t,
  ) async {
    final w = FakeWrapper()..noteParts = twoParts(noted: false);
    await openNotes(t, w);
    await t.enterText(find.byType(TextField), '   ');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settleSave(t);
    expect(w.calls.where((c) => c.contains('/markers/')), isEmpty);
    w.postStatus = 409;
    await t.enterText(find.byType(TextField), 'x');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settleSave(t);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget, reason: 'kept for a retry');
    await endNotes(t);
  });

  testWidgets('Esc in the field leaves it, the panel stays open', (t) async {
    var closed = 0;
    final w = FakeWrapper()..noteParts = twoParts(noted: false);
    await openNotes(t, w, onClose: () => closed++);
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, 0);
    await endNotes(t);
  });

  testWidgets('the image copy is the big first icon, text small and muted', (
    t,
  ) async {
    final w = FakeWrapper()..noteParts = twoParts();
    await openNotes(t, w);
    final files = t.getRect(label('copy notes 1 files'));
    final text = t.getRect(label('copy notes 1 text'));
    expect(files.left, lessThan(text.left));
    expect(files.height, greaterThan(text.height));
    Color? colorOf(IconData g) => t
        .widget<IconButton>(
          find.ancestor(
            of: find.byIcon(g).first,
            matching: find.byType(IconButton),
          ),
        )
        .color;
    expect(
      colorOf(Icons.text_snippet_rounded),
      isNot(colorOf(Icons.photo_library_rounded)),
    );
    await endNotes(t);
  });
}
