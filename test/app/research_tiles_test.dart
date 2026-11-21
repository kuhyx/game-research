import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_wrapper.dart';
import 'home_helpers.dart';

/// The picker shows blocked games with a lock; a tap asks (icons only) and
/// adds the game as research game; the slot holds one game.
/// No pumpAndSettle: the install bar of a research game animates forever.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  late FakeWrapper w;

  setUp(() {
    w = FakeWrapper()
      ..games = [
        {'appid': 1, 'name': 'One', 'lock': 'open'},
        {'appid': 7, 'name': 'Lib', 'state': 'absent', 'lock': 'blocked'},
        {'appid': 8, 'name': 'Dota', 'state': 'absent', 'lock': 'blocked'},
      ];
  });

  testWidgets('a blocked tile asks, then adds it as research game', (t) async {
    await pumpHome(t, w);
    expect(label('Lib, blocked'), findsOneWidget);
    await t.tap(label('Lib, blocked'));
    await _settle(t);
    expect(find.byIcon(Icons.science_rounded), findsOneWidget);
    expect(w.calls.where((c) => c.contains('research')), isEmpty);
    w.games[1]['lock'] = 'research';
    w.games[2]['lock'] = 'taken';
    await t.tap(find.bySemanticsLabel('confirm'));
    await _settle(t);
    expect(w.calls, contains('POST /api/research?appid=7'));
    expect(label('Lib, research'), findsOneWidget);
    expect(label('Dota, taken'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('slot taken')), findsOneWidget);
    await endHome(t);
  });

  testWidgets('cancel adds nothing; a taken tile does nothing', (t) async {
    w.games[1]['lock'] = 'research';
    w.games[2]['lock'] = 'taken';
    await pumpHome(t, w);
    await t.tap(label('Dota, taken'));
    await _settle(t);
    expect(find.byType(AlertDialog), findsNothing);
    await t.tap(find.bySemanticsLabel('remove research game'));
    await _settle(t);
    await t.tap(find.bySemanticsLabel('cancel'));
    await _settle(t);
    expect(w.calls.where((c) => c.contains('research')), isEmpty);
    await endHome(t);
  });

  testWidgets('the minus removes the research game', (t) async {
    w.games[1]['lock'] = 'research';
    await pumpHome(t, w);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await t.tap(find.bySemanticsLabel('remove research game'));
    await _settle(t);
    w.games[1]['lock'] = 'blocked';
    await t.tap(find.bySemanticsLabel('confirm'));
    await _settle(t);
    expect(w.calls, contains('POST /api/research/remove'));
    expect(label('Lib, blocked'), findsOneWidget);
    await endHome(t);
  });
}
