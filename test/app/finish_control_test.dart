import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/report_panel.dart';

import 'fake_wrapper.dart';
import 'home_helpers.dart';

void main() {
  group('finished control on the game tile', () {
    Map<String, Object?> game(Map<String, Object?>? finish) => {
      'appid': 1,
      'name': 'One',
      'capsule': false,
      'slug': 'one',
      'finish': finish,
    };

    FakeWrapper wrapper(Map<String, Object?>? finish, {bool draft = true}) =>
        FakeWrapper()
          ..docs['/r.md'] = '# Report'
          ..games = [game(finish)]
          ..sessions = [
            sessionRow('a', {
              'appid': 1,
              'draft': draft ? '/d.md' : null,
              'analysis': {'state': 'done', 'progress': 1},
            }),
          ];

    testWidgets('starts the merge once a session has a draft', (t) async {
      final w = wrapper(null);
      await pumpHome(t, w);
      await t.tap(label('finished 1'));
      await t.pump();
      await t.pump();
      expect(w.calls, contains('POST /api/games/1/finish'));
      await endHome(t);
    });

    testWidgets('running: a ring with progress; tap does not restart', (
      t,
    ) async {
      final w = wrapper({
        'state': 'running',
        'progress': 0.5,
        'tokens': {'in': 2000},
        'cost_usd': 1.5,
        'eta_s': 600,
      });
      await pumpHome(t, w);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('2k'), findsOneWidget);
      expect(find.text('1.50'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      await t.tap(label('finished 1'));
      await t.pump();
      expect(w.calls.where((c) => c.startsWith('POST /api/games')), isEmpty);
      await endHome(t);
    });

    testWidgets('done: the report opens in the panel', (t) async {
      final w = wrapper({'state': 'done', 'progress': 1, 'report': '/r.md'});
      await pumpHome(t, w);
      expect(find.byIcon(Icons.task_alt_rounded), findsOneWidget);
      await t.tap(label('finished 1'));
      await t.pump();
      await t.pump();
      expect(find.byType(ReportPanel), findsOneWidget);
      expect(w.calls, contains('GET /api/doc?path=%2Fr.md'));
      await t.tap(find.bySemanticsLabel(RegExp(r'^rerun$')));
      await t.pump();
      expect(w.calls, contains('POST /api/games/1/finish'));
      await endHome(t);
    });
  });
}
