import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/main.dart';

import 'fake_wrapper.dart';

/// kuhy 2026-11-11: show which global hotkey does what, as text beside each
/// marker button and the stop button.
void main() {
  Future<void> pump(WidgetTester t, {required bool recording}) async {
    t.view
      ..physicalSize = const Size(2048, 1152)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final w = FakeWrapper()..recording = recording;
    await t.pumpWidget(GameResearchApp(api: w.api()));
    await t.pump();
    await t.pump();
  }

  Future<void> end(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  }

  testWidgets('each marker and stop shows its hotkey', (t) async {
    await pump(t, recording: true);
    for (final keys in [
      'Super+F1',
      'Super+F2',
      'Super+F3',
      'Super+F4',
      'Super+Shift+F4',
    ]) {
      expect(find.text(keys), findsOneWidget, reason: keys);
    }
    final good = t.getSemantics(
      find.bySemanticsLabel(RegExp(r'^marker good$')),
    );
    expect(good.hint, 'Super+F1');
    final stop = t.getSemantics(find.bySemanticsLabel(RegExp(r'^stop$')));
    expect(stop.hint, 'Super+Shift+F4');
    await end(t);
  });

  testWidgets('idle: start has no hotkey, markers still show theirs', (
    t,
  ) async {
    await pump(t, recording: false);
    expect(find.text('Super+Shift+F4'), findsNothing);
    expect(find.text('Super+F1'), findsOneWidget);
    await end(t);
  });
}
