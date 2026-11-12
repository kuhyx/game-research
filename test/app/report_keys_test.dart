import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_wrapper.dart';
import 'reader_fixtures.dart';
import 'reader_helpers.dart';

void main() {
  setUpAll(loadInter);
  setUp(() => readerPointer = null);

  group('keys', () {
    testWidgets('Esc closes the reader', (t) async {
      final w = FakeWrapper()..docs['/t/a.md'] = '# A';
      var closed = 0;
      await openReader(t, w, onClose: () => closed++);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 1);
    });

    testWidgets('Esc in edit mode leaves it first and keeps the edit', (
      t,
    ) async {
      final w = FakeWrapper()..docs['/t/a.md'] = '# Old';
      var closed = 0;
      await openReader(t, w, onClose: () => closed++);
      await reveal(t);
      await t.tap(label('edit'));
      await t.pump();
      await t.enterText(find.byType(TextField), '# Unsaved');
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(closed, 0);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.textContaining('Unsaved', findRichText: true),
        findsOneWidget,
      );
      expect(w.docs['/t/a.md'], '# Old', reason: 'not saved either');
    });

    testWidgets('Esc in read mode never discards unsaved edits', (t) async {
      final w = FakeWrapper()..docs['/t/a.md'] = '# Old';
      var closed = 0;
      await openReader(t, w, onClose: () => closed++);
      await reveal(t);
      await t.tap(label('edit'));
      await t.pump();
      await t.enterText(find.byType(TextField), '# Unsaved');
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(closed, 0, reason: 'dirty text must survive Esc');
      expect(
        find.textContaining('Unsaved', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('edit mode: arrows and paging stay in the field', (t) async {
      final w = FakeWrapper()..docs['/t/a.md'] = draftFixture();
      await openReader(t, w);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      await reveal(t);
      await t.tap(label('edit'));
      await t.pump();
      final field = find.byType(TextField);
      await t.tap(field);
      await t.pump();
      TextEditingController ctl() => t.widget<TextField>(field).controller!;
      ctl().selection = const TextSelection.collapsed(offset: 5);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(ctl().selection.baseOffset, 4);
      for (final k in [
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.pageUp,
      ]) {
        await t.sendKeyEvent(k);
      }
      await t.pump();
      await t.tap(label('edit'));
      await t.pump();
      await reveal(t);
      expect(pageOf(t).startsWith('2/'), isTrue, reason: 'page did not flip');
    });
  });
}
