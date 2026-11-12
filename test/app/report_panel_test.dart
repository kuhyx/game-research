import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/report_panel.dart';

import 'fake_wrapper.dart';

Finder _label(String l) =>
    find.bySemanticsLabel(RegExp('^${RegExp.escape(l)}'));

Future<void> _open(
  WidgetTester t,
  FakeWrapper w, {
  String path = '/t/a.md',
  VoidCallback? onClose,
}) async {
  t.view
    ..physicalSize = const Size(2048, 1152)
    ..devicePixelRatio = 1;
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

void main() {
  testWidgets('shows the markdown rendered, not as source', (t) async {
    final w = FakeWrapper()..docs['/t/a.md'] = '# Heading\n\n- **bold** item';
    await _open(t, w);
    expect(w.calls, ['GET /api/doc?path=%2Ft%2Fa.md']);
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.textContaining('Heading', findRichText: true), findsOneWidget);
    expect(find.textContaining('# Heading', findRichText: true), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('edit toggle shows the source; save writes it back', (t) async {
    final w = FakeWrapper()..docs['/t/a.md'] = '# Old';
    await _open(t, w);
    await t.tap(_label('edit'));
    await t.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('# Old'), findsOneWidget);
    await t.enterText(find.byType(TextField), '# New');
    await t.pump();
    await t.tap(_label('save'));
    await t.pump();
    await t.pump();
    expect(w.docs['/t/a.md'], '# New');
    expect(w.calls.last, 'PUT /api/doc?path=%2Ft%2Fa.md # New');
    await t.tap(_label('edit'));
    await t.pump();
    expect(find.textContaining('New', findRichText: true), findsOneWidget);
  });

  testWidgets('save is off until the text changed', (t) async {
    final w = FakeWrapper()..docs['/t/a.md'] = '# Old';
    await _open(t, w);
    await t.tap(_label('edit'));
    await t.pump();
    await t.tap(_label('save'));
    await t.pump();
    expect(w.calls.where((c) => c.startsWith('PUT')), isEmpty);
  });

  testWidgets('a refused or missing document shows the error glyph', (t) async {
    await _open(t, FakeWrapper(), path: '/etc/passwd');
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
  });

  testWidgets('a failed save keeps the edit and shows the error', (t) async {
    final w = FakeWrapper()..docs['/t/a.md'] = '# Old';
    await _open(t, w);
    await t.tap(_label('edit'));
    await t.pump();
    await t.enterText(find.byType(TextField), '# New');
    await t.pump();
    w.docs.remove('/t/a.md');
    await t.tap(_label('save'));
    await t.pump();
    await t.pump();
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('# New'), findsOneWidget, reason: 'edit not lost');
  });

  testWidgets('close calls back; there is no rerun button', (t) async {
    final w = FakeWrapper()..docs['/t/a.md'] = '# A';
    var closed = 0;
    await _open(t, w, onClose: () => closed++);
    expect(_label('rerun'), findsNothing);
    await t.tap(_label('close'));
    expect(closed, 1);
  });

  testWidgets('a new path loads the new document', (t) async {
    final w = FakeWrapper()
      ..docs['/t/a.md'] = '# First'
      ..docs['/t/b.md'] = '# Second';
    await _open(t, w);
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
}
