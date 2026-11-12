import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/doc_page_view.dart';
import 'package:game_research/app/report_panel.dart';

import 'fake_wrapper.dart';
import 'home_helpers.dart';

void main() {
  testWidgets('a session row shows tokens, cost, stage, eta and fps', (
    t,
  ) async {
    final w = FakeWrapper()
      ..sessions = [
        sessionRow('a', {
          'fps': {'avg': 59.6},
          'analysis': {
            'state': 'running',
            'stage': 2,
            'done': 5,
            'total': 40,
            'progress': 0.4,
            'tokens': {
              'in': 1000,
              'out': 200,
              'cache_read': 30,
              'cache_write': 4,
            },
            'cost_usd': 0.4,
            'eta_s': 125,
          },
        }),
      ];
    await pumpHome(t, w);
    expect(find.text('1.2k'), findsOneWidget, reason: 'token total');
    expect(find.text('0.40'), findsOneWidget, reason: 'cost');
    expect(find.text('5/40'), findsOneWidget, reason: 'done/total');
    expect(find.text('3'), findsOneWidget, reason: 'minutes left');
    expect(find.text('60'), findsWidgets, reason: 'fps');
    expect(label('tokens'), findsOneWidget);
    await endHome(t);
  });

  testWidgets('an old row (no new fields) shows no stats', (t) async {
    final w = FakeWrapper()
      ..sessions = [
        sessionRow('a', {
          'analysis': {'state': 'done', 'progress': 1},
        }),
      ];
    await pumpHome(t, w);
    expect(label('tokens'), findsNothing);
    expect(label('cost'), findsNothing);
    expect(label('fps'), findsNothing);
    await endHome(t);
  });

  testWidgets('waiting and interrupted jobs get their own glyphs', (t) async {
    final w = FakeWrapper()
      ..sessions = [
        sessionRow('a', {
          'analysis': {'state': 'waiting', 'progress': 0.7},
        }),
        sessionRow('b', {
          'analysis': {'state': 'interrupted', 'progress': 0.2},
        }),
      ];
    await pumpHome(t, w);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await endHome(t);
  });

  testWidgets('the draft button opens the in-app panel, no POST', (t) async {
    final w = FakeWrapper()
      ..docs['/d.md'] = '# Draft title'
      ..sessions = [
        sessionRow('a', {
          'draft': '/d.md',
          'analysis': {'state': 'done', 'progress': 1},
        }),
      ];
    await pumpHome(t, w);
    expect(find.byType(ReportPanel), findsNothing);
    await t.tap(label('draft a'));
    await t.pump();
    await t.pump();
    expect(find.byType(ReportPanel), findsOneWidget);
    expect(w.calls, contains('GET /api/doc?path=%2Fd.md'));
    expect(w.calls.where((c) => c.contains('open-draft')), isEmpty);
    expect(find.byType(DocPageView), findsOneWidget);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 600));
    await mouse.moveTo(const Offset(400, 2));
    await t.pumpAndSettle();
    await t.tap(label('close'));
    await t.pump();
    expect(find.byType(ReportPanel), findsNothing);
    await endHome(t);
  });

  group('stray clicks (open-draft fired on its own)', () {
    Future<FakeWrapper> setup(WidgetTester t) async {
      final w = FakeWrapper()
        ..docs['/d.md'] = '# D'
        ..sessions = [
          sessionRow('a', {
            'draft': '/d.md',
            'analysis': {'state': 'done', 'progress': 1},
          }),
        ];
      await pumpHome(t, w);
      return w;
    }

    testWidgets('row buttons ignore taps just after a game ends', (t) async {
      final w = await setup(t);
      w.recording = true;
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      w.recording = false;
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      await t.tap(label('draft a'));
      await t.pump();
      expect(w.calls.where((c) => c.contains('/api/doc')), isEmpty);
      await t.pump(const Duration(seconds: 6));
      await t.tap(label('draft a'));
      await t.pump();
      await t.pump();
      expect(w.calls.where((c) => c.contains('/api/doc')), isNotEmpty);
      await endHome(t);
    });

    testWidgets('and just after the page opened by the launcher', (t) async {
      final w = FakeWrapper()
        ..docs['/d.md'] = '# D'
        ..sessions = [
          sessionRow('a', {
            'draft': '/d.md',
            'analysis': {'state': 'done', 'progress': 1},
          }),
        ];
      await pumpHome(t, w, autostart: true);
      await t.tap(label('draft a'));
      await t.pump();
      expect(find.byType(ReportPanel), findsNothing);
      await t.pump(const Duration(seconds: 6));
      await t.tap(label('draft a'));
      await t.pump();
      expect(find.byType(ReportPanel), findsOneWidget);
      await endHome(t);
    });
  });

  testWidgets('a wrapper without /api/finish still works', (t) async {
    final w = FakeWrapper()..noFinish = true;
    await pumpHome(t, w);
    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    expect(label('One'), findsOneWidget);
    await endHome(t);
  });

  testWidgets('a second marker closes the open note line empty first', (
    t,
  ) async {
    final w = FakeWrapper();
    await pumpHome(t, w);
    await t.tap(label('One'));
    await t.pump();
    await t.tap(label('start'));
    await t.pump();
    await t.pump();
    await t.tap(label('marker good'));
    await t.pump();
    await t.pump();
    await t.tap(label('marker bad'));
    await t.pump();
    await t.pump();
    final i = w.calls.indexOf('POST /api/note?id=7');
    expect(i, greaterThan(-1));
    expect(
      w.calls.indexOf('POST /api/marker?tag=bad&src=gui&hold=1'),
      greaterThan(i),
    );
    await endHome(t);
  });
}
