import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/doc_page_view.dart';
import 'package:game_research/app/reader_toolbar.dart';
import 'package:game_research/app/report_panel.dart';

import 'fake_wrapper.dart';

Finder label(String l) => find.bySemanticsLabel(RegExp('^${RegExp.escape(l)}'));

const kTopEdge = Offset(900, 3);
const kMiddle = Offset(900, 600);

/// Opens the reader on [path] at the given window size.
Future<void> openReader(
  WidgetTester t,
  FakeWrapper w, {
  String path = '/t/a.md',
  VoidCallback? onClose,
  Size size = const Size(3840, 2160),
  double dpr = 2,
}) async {
  t.view
    ..physicalSize = size
    ..devicePixelRatio = dpr;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReportPanel(api: w.api(), path: path, onClose: onClose ?? () {}),
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

TestGesture? readerPointer;

/// The test's one mouse, put at [at].
Future<TestGesture> mouse(WidgetTester t, Offset at) async {
  final g = readerPointer;
  if (g == null) {
    final made = readerPointer = await t.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await made.addPointer(location: at);
  } else {
    await g.moveTo(at);
  }
  await t.pumpAndSettle();
  return readerPointer!;
}

Future<TestGesture> reveal(WidgetTester t) async {
  final g = await mouse(t, kMiddle);
  await g.moveTo(kTopEdge);
  await t.pumpAndSettle();
  return g;
}

double toolbarBottom(WidgetTester t) =>
    t.getBottomLeft(find.byKey(kReaderToolbarKey)).dy;

String pageOf(WidgetTester t) {
  final s = t.getSemantics(label('page'));
  return s.value;
}

int blocksShown(WidgetTester t) => find.byType(DocBlockView).evaluate().length;
