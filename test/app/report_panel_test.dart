import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/doc_blocks.dart';
import 'package:game_research/app/doc_page_view.dart';
import 'package:game_research/app/report_panel.dart';

import 'fake_wrapper.dart';
import 'reader_fixtures.dart';
import 'reader_helpers.dart';

void main() {
  setUpAll(loadInter);
  setUp(() => readerPointer = null);

  testWidgets('shows the markdown rendered, not as source', (t) async {
    final w = FakeWrapper()..docs['/t/a.md'] = '# Heading\n\n- **bold** item';
    await openReader(t, w);
    expect(w.calls, ['GET /api/doc?path=%2Ft%2Fa.md']);
    expect(find.byType(DocPageView), findsOneWidget);
    expect(find.textContaining('Heading', findRichText: true), findsOneWidget);
    expect(find.textContaining('# Heading', findRichText: true), findsNothing);
    expect(find.textContaining('**', findRichText: true), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Scrollable), findsNothing);
  });

  testWidgets('the ~650-word report is one page, 3 columns, no overflow', (
    t,
  ) async {
    for (final (size, dpr) in [
      (const Size(3840, 2160), 2.0),
      (const Size(3840, 2160), 1.0),
    ]) {
      final w = FakeWrapper()..docs['/t/a.md'] = reportFixture();
      await openReader(t, w, size: size, dpr: dpr);
      expect(t.takeException(), isNull);
      expect(find.byType(DocColumnView), findsNWidgets(3));
      expect(blocksShown(t), parseDoc(reportFixture()).length);
      await reveal(t);
      expect(pageOf(t), '1/1');
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('the draft pages; every block on exactly one page', (t) async {
    final w = FakeWrapper()..docs['/t/a.md'] = draftFixture();
    await openReader(t, w);
    expect(t.takeException(), isNull);
    await reveal(t);
    final count = int.parse(pageOf(t).split('/').last);
    expect(count, greaterThanOrEqualTo(3));
    var shown = 0;
    for (var p = 1; p <= count; p++) {
      expect(pageOf(t), '$p/$count');
      shown += blocksShown(t);
      expect(t.takeException(), isNull);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
    }
    expect(pageOf(t), '$count/$count', reason: 'no flip past the end');
    expect(shown, parseDoc(draftFixture()).length);
  });

  testWidgets('arrows and PageUp/PageDown flip, clamped at both ends', (
    t,
  ) async {
    final w = FakeWrapper()..docs['/t/a.md'] = draftFixture();
    await openReader(t, w);
    await reveal(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(pageOf(t).startsWith('1/'), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(pageOf(t).startsWith('2/'), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
    expect(pageOf(t).startsWith('3/'), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await t.pump();
    expect(pageOf(t).startsWith('2/'), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(pageOf(t).startsWith('1/'), isTrue);
  });

  testWidgets('the mouse wheel flips pages too', (t) async {
    final w = FakeWrapper()..docs['/t/a.md'] = draftFixture();
    await openReader(t, w);
    await reveal(t);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await t.sendEventToBinding(pointer.hover(kMiddle));
    await t.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await t.pump();
    expect(pageOf(t).startsWith('2/'), isTrue);
    await t.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await t.pump();
    expect(pageOf(t).startsWith('1/'), isTrue);
  });

  testWidgets('open questions collapse into one ids line', (t) async {
    final w = FakeWrapper()..docs['/t/a.md'] = draftFixture();
    await openReader(t, w);
    await reveal(t);
    final count = int.parse(pageOf(t).split('/').last);
    var found = 0;
    for (var p = 0; p < count; p++) {
      found += find
          .textContaining('Q1.4 · Q1.8 · Q2.4', findRichText: true)
          .evaluate()
          .length;
      expect(find.textContaining('Status', findRichText: true), findsNothing);
      expect(find.textContaining('STATUS', findRichText: true), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
    }
    expect(found, 1);
  });

  testWidgets('a block taller than a column renders without overflow', (
    t,
  ) async {
    final w = FakeWrapper()
      ..docs['/t/a.md'] = '# Big\n\n${words(3, 2500)}\n\nend';
    await openReader(t, w);
    expect(t.takeException(), isNull);
    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('a new path loads the new document', (t) async {
    final w = FakeWrapper()
      ..docs['/t/a.md'] = '# First'
      ..docs['/t/b.md'] = '# Second';
    await openReader(t, w);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportPanel(api: w.api(), path: '/t/b.md', onClose: () {}),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    expect(find.textContaining('Second', findRichText: true), findsOneWidget);
    expect(find.textContaining('First', findRichText: true), findsNothing);
  });

  testWidgets('the reader paints opaque #16181D over the whole window', (
    t,
  ) async {
    final w = FakeWrapper()..docs['/t/a.md'] = '# A';
    await openReader(t, w);
    final box = t.getSize(find.byType(ReportPanel));
    expect(box, const Size(1920, 1080));
    final colored = find.descendant(
      of: find.byType(ReportPanel),
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFF16181D),
      ),
    );
    expect(colored, findsWidgets);
  });
}
