import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/report_panel.dart';

import 'fake_wrapper.dart';
import 'home_helpers.dart';

// kuhy, 2026-11-12: the flag was pressed and no finish POST ever reached the
// wrapper. Pressing it must always send the request (nothing to merge yet,
// a page just opened by the launcher), and the report opens from a row.
void main() {
  Map<String, Object?> game(Map<String, Object?>? finish) => {
    'appid': 1,
    'name': 'One',
    'capsule': false,
    'finish': finish,
  };

  FakeWrapper wrapper(Map<String, Object?>? finish, {bool draft = false}) =>
      FakeWrapper()
        ..docs['/r.md'] = '# Report'
        ..games = [game(finish)]
        ..sessions = [
          sessionRow('a', {
            'appid': 1,
            'draft': draft ? '/d.md' : null,
            'analysis': {'state': 'running', 'stage': 2, 'progress': 0.3},
          }),
        ];

  bool posted(FakeWrapper w) => w.calls.contains('POST /api/games/1/finish');

  testWidgets('no draft yet: pressing still sends the request', (t) async {
    final w = wrapper(null);
    await pumpHome(t, w);
    await t.tap(label('finished 1'));
    await t.pump();
    await t.pump();
    expect(posted(w), isTrue);
    await endHome(t);
  });

  testWidgets('right after the launcher opened the page: still sent', (
    t,
  ) async {
    final w = wrapper(null);
    await pumpHome(t, w, autostart: true);
    await t.tap(label('finished 1'));
    await t.pump();
    expect(posted(w), isTrue, reason: 'the 5 s tap guard must not eat it');
    await endHome(t);
  });

  testWidgets('queued reads as waiting: amber hourglass, no second POST', (
    t,
  ) async {
    final w = wrapper({'state': 'waiting', 'progress': 0.0});
    await pumpHome(t, w);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsWidgets);
    await t.tap(label('finished 1'));
    await t.pump();
    expect(posted(w), isFalse);
    await endHome(t);
  });

  testWidgets('a failed job: pressing asks again', (t) async {
    final w = wrapper({'state': 'failed'});
    await pumpHome(t, w);
    await t.tap(label('finished 1'));
    await t.pump();
    expect(posted(w), isTrue);
    await endHome(t);
  });

  testWidgets('done: the session row opens the report in the panel', (t) async {
    final w = wrapper({'state': 'done', 'progress': 1, 'report': '/r.md'});
    await pumpHome(t, w);
    await t.tap(label('report a'));
    await t.pump();
    await t.pump();
    expect(find.byType(ReportPanel), findsOneWidget);
    expect(w.calls, contains('GET /api/doc?path=%2Fr.md'));
    await endHome(t);
  });

  testWidgets('no report yet: the row has no report button', (t) async {
    final w = wrapper({'state': 'running', 'progress': 0.4});
    await pumpHome(t, w);
    expect(label('report a'), findsNothing);
    await endHome(t);
  });
}
