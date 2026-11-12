import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/notes_panel.dart';
import 'package:game_research/app/report_panel.dart';

import 'fake_wrapper.dart';
import 'home_helpers.dart';
import 'notes_fixtures.dart';
import 'reader_fixtures.dart';
import 'reader_helpers.dart' show kMiddle, kTopEdge, mouse, readerPointer;

void main() {
  setUpAll(loadInter);
  setUp(() => readerPointer = null);

  FakeWrapper wrapper() => FakeWrapper()
    ..docs['/r.md'] = '# Report'
    ..docs['/d.md'] = '# Draft'
    ..noteParts = twoParts()
    ..games = [
      {
        'appid': 1,
        'name': 'One',
        'capsule': false,
        'slug': 'one',
        'finish': {'state': 'done', 'progress': 1, 'report': '/r.md'},
      },
    ]
    ..sessions = [
      sessionRow('a', {
        'appid': 1,
        'draft': '/d.md',
        'analysis': {'state': 'done', 'progress': 1},
      }),
    ];

  Future<void> reveal(WidgetTester t) async {
    final g = await mouse(t, kMiddle);
    await g.moveTo(kTopEdge);
    await t.pumpAndSettle();
  }

  testWidgets('the report opens the notes of its game; closing returns', (
    t,
  ) async {
    final w = wrapper();
    await pumpHome(t, w);
    await t.tap(label('finished 1'));
    await t.pump();
    await t.pump();
    await reveal(t);
    await t.tap(label('my notes'));
    await t.pump();
    await t.pump();
    expect(find.byType(NotesPanel), findsOneWidget);
    expect(w.calls, contains('GET /api/games/1/notes'));
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.byType(NotesPanel), findsNothing);
    expect(find.byType(ReportPanel), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.byType(ReportPanel), findsNothing, reason: 'focus came back');
    await endHome(t);
  });

  testWidgets('a draft has no notes icon', (t) async {
    final w = wrapper();
    await pumpHome(t, w);
    await t.tap(label('draft a'));
    await t.pump();
    await t.pump();
    await reveal(t);
    expect(find.byType(ReportPanel), findsOneWidget);
    expect(label('my notes'), findsNothing);
    await endHome(t);
  });
}
