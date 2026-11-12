import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/stat_words.dart';

import 'fake_wrapper.dart';
import 'home_helpers.dart';

// kuhy, 2026-11-12: "in this case I want one word text" under each
// session-row stat; stages become scan / captions / draft icons.
Map<String, Object?> _row(String state, int stage, {Object? tokens}) =>
    sessionRow('a', {
      'analysis': {
        'state': state,
        'stage': stage,
        'progress': 0.4,
        'tokens': ?tokens,
        'cost_usd': 1.77,
      },
    });

Color? _iconColor(WidgetTester t, IconData icon) =>
    t.widget<Icon>(find.byIcon(icon)).color;

void main() {
  test('compactTokens: 950k, 1.8M, no thousands spaces', () {
    expect(compactTokens(0), '0');
    expect(compactTokens(999), '999');
    expect(compactTokens(1000), '1k');
    expect(compactTokens(1234), '1.2k');
    expect(compactTokens(950400), '950k');
    expect(compactTokens(999999), '1M');
    expect(compactTokens(1758154), '1.8M');
    expect(compactTokens(12300000), '12M');
  });

  test('every stat word lives in the one map', () {
    expect(kStatWords, {
      'tokens': 'tokens',
      'cost': 'cost',
      'scan': 'scan',
      'captions': 'captions',
      'draft': 'draft',
    });
  });

  testWidgets('a session row: coin + 1.8M, cost, one word under each', (
    t,
  ) async {
    final w = FakeWrapper()
      ..sessions = [
        _row('running', 2, tokens: {'in': 1758154}),
      ];
    await pumpHome(t, w);
    expect(find.text('1.8M'), findsOneWidget);
    expect(find.text('1 758 154'), findsNothing);
    expect(find.byIcon(Icons.toll_rounded), findsOneWidget);
    expect(find.text('1.77'), findsOneWidget);
    for (final word in kStatWords.values) {
      expect(find.text(word), findsOneWidget, reason: word);
    }
    await endHome(t);
  });

  testWidgets('stage 2 running: scan green+check, captions lit, draft grey', (
    t,
  ) async {
    final w = FakeWrapper()..sessions = [_row('running', 2)];
    await pumpHome(t, w);
    expect(_iconColor(t, Icons.videocam_rounded), AppPalette.success);
    expect(_iconColor(t, Icons.visibility_rounded), AppPalette.accent);
    expect(_iconColor(t, Icons.description_outlined), AppPalette.mutedOnDark);
    expect(find.byIcon(Icons.done_rounded), findsNWidgets(1));
    await endHome(t);
  });

  testWidgets('done: all three green with a check; not started: grey', (
    t,
  ) async {
    final w = FakeWrapper()..sessions = [_row('done', 3)];
    await pumpHome(t, w);
    for (final i in [
      Icons.videocam_rounded,
      Icons.visibility_rounded,
      Icons.description_outlined,
    ]) {
      expect(_iconColor(t, i), AppPalette.success);
    }
    expect(find.byIcon(Icons.done_rounded), findsWidgets);
    w.sessions = [_row('running', 0)];
    await t.pump(const Duration(seconds: 2));
    await t.pump();
    expect(_iconColor(t, Icons.videocam_rounded), AppPalette.mutedOnDark);
    await endHome(t);
  });

  testWidgets('a failed stage is red; the game tile has no words', (t) async {
    final w = FakeWrapper()
      ..games = [
        {
          'appid': 1,
          'name': 'One',
          'capsule': false,
          'finish': {
            'state': 'running',
            'progress': 0.5,
            'stage': 1,
            'tokens': {'in': 2000},
            'cost_usd': 1.5,
          },
        },
      ]
      ..sessions = [_row('failed', 3)];
    await pumpHome(t, w);
    expect(_iconColor(t, Icons.description_outlined), AppPalette.danger);
    // Session row words: one each. The tile adds none.
    expect(find.text('tokens'), findsNothing);
    expect(find.text('cost'), findsOneWidget);
    expect(find.text('scan'), findsOneWidget);
    expect(find.text('2k'), findsOneWidget, reason: 'tile tokens, compact');
    await endHome(t);
  });
}
