import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/doc_page_view.dart';

import 'fake_wrapper.dart';
import 'reader_fixtures.dart';
import 'reader_helpers.dart';

void main() {
  setUpAll(loadInter);
  setUp(() => readerPointer = null);

  group('toolbar', () {
    testWidgets('hidden at first; the top edge slides it in, leaving out', (
      t,
    ) async {
      final w = FakeWrapper()..docs['/t/a.md'] = '# A';
      await openReader(t, w);
      expect(toolbarBottom(t), lessThanOrEqualTo(0));
      final g = await mouse(t, kMiddle);
      expect(toolbarBottom(t), lessThanOrEqualTo(0));
      await g.moveTo(kTopEdge);
      await t.pumpAndSettle();
      expect(toolbarBottom(t), greaterThan(20));
      await g.moveTo(const Offset(900, 40));
      await t.pumpAndSettle();
      expect(toolbarBottom(t), greaterThan(20), reason: 'still over it');
      await g.moveTo(kMiddle);
      await t.pumpAndSettle();
      expect(toolbarBottom(t), lessThanOrEqualTo(0));
    });

    testWidgets('edit toggle shows the source; save writes it back', (t) async {
      final w = FakeWrapper()..docs['/t/a.md'] = '# Old';
      await openReader(t, w);
      await reveal(t);
      await t.tap(label('edit'));
      await t.pump();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('# Old'), findsOneWidget);
      await t.enterText(find.byType(TextField), '# New');
      await t.pump();
      await t.tap(label('save'));
      await t.pump();
      await t.pump();
      expect(w.docs['/t/a.md'], '# New');
      expect(w.calls.last, 'PUT /api/doc?path=%2Ft%2Fa.md # New');
      await t.tap(label('edit'));
      await t.pump();
      expect(find.textContaining('New', findRichText: true), findsOneWidget);
    });

    testWidgets('save is off until the text changed', (t) async {
      final w = FakeWrapper()..docs['/t/a.md'] = '# Old';
      await openReader(t, w);
      await reveal(t);
      await t.tap(label('edit'));
      await t.pump();
      await t.tap(label('save'));
      await t.pump();
      expect(w.calls.where((c) => c.startsWith('PUT')), isEmpty);
    });

    testWidgets('a refused or missing document shows the error glyph', (
      t,
    ) async {
      await openReader(t, FakeWrapper(), path: '/etc/passwd');
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byType(DocPageView), findsNothing);
    });

    testWidgets('a failed save keeps the edit and shows the error', (t) async {
      final w = FakeWrapper()..docs['/t/a.md'] = '# Old';
      await openReader(t, w);
      await reveal(t);
      await t.tap(label('edit'));
      await t.pump();
      await t.enterText(find.byType(TextField), '# New');
      await t.pump();
      w.docs.remove('/t/a.md');
      await t.tap(label('save'));
      await t.pump();
      await t.pump();
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('# New'), findsOneWidget, reason: 'edit not lost');
    });

    testWidgets('close calls back; there is no rerun button', (t) async {
      final w = FakeWrapper()..docs['/t/a.md'] = '# A';
      var closed = 0;
      await openReader(t, w, onClose: () => closed++);
      await reveal(t);
      expect(label('rerun'), findsNothing);
      await t.tap(label('close'));
      expect(closed, 1);
    });

    testWidgets('a saved edit shows the check', (t) async {
      final w = FakeWrapper()..docs['/t/a.md'] = '# A';
      await openReader(t, w);
      await reveal(t);
      await t.tap(label('edit'));
      await t.pump();
      await t.enterText(find.byType(TextField), '# B');
      await t.pump();
      await t.tap(label('save'));
      await t.pump();
      await t.pump();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });
}
