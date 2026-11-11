import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/game_picker.dart';
import 'package:game_research/app/home_screen.dart';
import 'package:game_research/main.dart';

import 'fake_wrapper.dart';

Future<void> _pump(WidgetTester tester, FakeWrapper w) async {
  tester.view
    ..physicalSize = const Size(2048, 1152)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    GameResearchApp(api: w.api()).build(tester.element(find.byType(Container)))
            is MaterialApp
        ? MaterialApp(
            home: HomeScreen(api: w.api(), now: () => 165),
          )
        : const SizedBox(),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

Finder _label(String l) =>
    find.bySemanticsLabel(RegExp('^${RegExp.escape(l)}'));

void main() {
  testWidgets('pick, start, markers, note by Enter and Esc, stop', (t) async {
    final w = FakeWrapper();
    await _pump(t, w);
    expect(find.byType(ProceduralCapsule), findsWidgets);
    await t.tap(_label('One'));
    await t.pump();
    await t.tap(_label('start'));
    await t.pump();
    await t.pump();
    expect(w.calls, contains('POST /api/start?appid=1'));
    expect(_label('stop'), findsOneWidget);
    expect(find.text('01:05'), findsOneWidget);
    await t.tap(_label('marker good'));
    await t.pump();
    await t.tap(_label('marker note'));
    await t.pump();
    await t.pump();
    await t.enterText(find.byType(TextField), 'a note');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await t.pump();
    expect(w.calls, contains('POST /api/note?id=7 a note'));
    await t.tap(_label('marker note'));
    await t.pump();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    await t.pump();
    expect(w.calls, contains('POST /api/note?id=7'));
    await t.tap(_label('stop'));
    await t.pump();
    await t.pump();
    await t.pump();
    expect(w.calls, contains('POST /api/stop'));
    expect(_label('start'), findsOneWidget);
    await _end(t);
  });

  testWidgets('target chip, rerun and draft buttons, ring states', (t) async {
    final w = FakeWrapper()
      ..sessions = [
        for (final (id, state, draft) in [
          ('a', 'done', '/d.md'),
          ('b', 'failed', null),
          ('c', 'running', null),
        ])
          {
            'id': id,
            'appid': 2,
            'started_unix': 0,
            'analysis': {'state': state, 'progress': 0.5},
            'draft': draft,
          },
      ];
    await _pump(t, w);
    await t.tap(find.text('other'));
    await t.pump();
    await t.pump();
    expect(w.calls, contains('POST /api/target /src/other'));
    await t.tap(_label('rerun a'));
    await t.tap(_label('draft a'));
    await t.pump();
    expect(w.calls, contains('POST /api/sessions/a/analyze'));
    expect(w.calls, contains('POST /api/sessions/a/open-draft'));
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await _end(t);
  });

  testWidgets('one game is picked by itself; a failed start shows', (t) async {
    final w = FakeWrapper()
      ..games = [
        {'appid': 9, 'name': 'Solo', 'capsule': false},
      ]
      ..error = 'no encoder'
      ..postStatus = 409;
    await _pump(t, w);
    expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    await t.tap(_label('start'));
    await t.pump();
    await t.pump();
    expect(w.calls, contains('POST /api/start?appid=9'));
    await _end(t);
  });

  testWidgets('no games shows the empty glyph; offline the cloud', (t) async {
    final w = FakeWrapper()..games = [];
    await _pump(t, w);
    expect(find.byIcon(Icons.videogame_asset_off_rounded), findsOneWidget);
    w.offline = true;
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    await _end(t);
  });

  testWidgets('the app wraps the home screen in the dark theme', (t) async {
    t.view
      ..physicalSize = const Size(2048, 1152)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final w = FakeWrapper()..recording = true;
    await t.pumpWidget(GameResearchApp(api: w.api()));
    await t.pump();
    await t.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
    await _end(t);
  });

  testWidgets('offline from the start', (t) async {
    final w = FakeWrapper()..offline = true;
    await _pump(t, w);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    await _end(t);
  });
}
