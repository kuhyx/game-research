import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/copy_icon.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpIcon(WidgetTester t, Future<void> Function()? onCopy) =>
    t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CopyIcon(semantic: 'copy it', size: 40, onCopy: onCopy),
        ),
      ),
    );

Finder label(String l) => find.bySemanticsLabel(RegExp('^${RegExp.escape(l)}'));

void main() {
  testWidgets('copy glyph, spinner while it runs, check for 1.5 s', (t) async {
    final gate = Completer<void>();
    var calls = 0;
    await pumpIcon(t, () {
      calls++;
      return gate.future;
    });
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
    await t.tap(label('copy it'));
    await t.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsNothing);
    await t.tap(find.byType(CopyIcon), warnIfMissed: false);
    expect(calls, 1, reason: 'a second tap while busy is ignored');
    gate.complete();
    await t.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1400));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
  });

  testWidgets('a failure shows the error glyph until the next tap', (t) async {
    var fail = true;
    await pumpIcon(t, () async {
      if (fail) throw const ApiError(409, 'stills not all cut yet');
    });
    await t.tap(label('copy it'));
    await t.pump();
    await t.pump();
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    fail = false;
    await t.tap(label('copy it'));
    await t.pump();
    await t.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('disabled without a callback', (t) async {
    await pumpIcon(t, null);
    final button = t.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
  });

  testWidgets('leaving while busy or showing the check is harmless', (t) async {
    final gate = Completer<void>();
    await pumpIcon(t, () => gate.future);
    await t.tap(label('copy it'));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    gate.complete();
    await t.pump();
    await pumpIcon(t, () async {});
    await t.tap(label('copy it'));
    await t.pump();
    await t.pump();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
    expect(t.takeException(), isNull);
  });
}
