import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_wrapper.dart';
import 'home_helpers.dart';

// Stage 1 reports 1000 units (ffmpeg time), a waiting job keeps its stage
// progress, an interrupted one shows the pause glyph over its ring.
void main() {
  CircularProgressIndicator ring(WidgetTester t) =>
      t.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator).first,
      );

  testWidgets('stage 1 of 1000 units: ring moves, no 237/1000 text', (t) async {
    final w = FakeWrapper()
      ..sessions = [
        sessionRow('a', {
          'analysis': {
            'state': 'running',
            'stage': 1,
            'done': 237,
            'total': 1000,
            'progress': 0.079,
            'eta_s': 90,
          },
        }),
      ];
    await pumpHome(t, w);
    expect(ring(t).value, closeTo(0.079, 1e-9));
    expect(find.text('237/1000'), findsNothing);
    expect(label('items'), findsNothing);
    expect(label('stage'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'minutes left');
    await endHome(t);
  });

  testWidgets('stage 2 shows done/total next to the ring', (t) async {
    final w = FakeWrapper()
      ..sessions = [
        sessionRow('a', {
          'analysis': {
            'state': 'running',
            'stage': 2,
            'done': 5,
            'total': 40,
            'progress': 0.45,
          },
        }),
      ];
    await pumpHome(t, w);
    expect(find.text('5/40'), findsOneWidget);
    await endHome(t);
  });

  testWidgets('waiting: partial ring, hourglass, no 0/1 and no eta', (t) async {
    final w = FakeWrapper()
      ..sessions = [
        sessionRow('a', {
          'analysis': {
            'state': 'waiting',
            'stage': 3,
            'done': 0,
            'total': 1,
            'progress': 0.667,
            'error': 'queued behind x',
          },
        }),
      ];
    await pumpHome(t, w);
    expect(ring(t).value, closeTo(0.667, 1e-9));
    expect(ring(t).color, AppPalette.warning);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.text('0/1'), findsNothing);
    expect(label('minutes left'), findsNothing);
    expect(label('analysis waiting'), findsOneWidget);
    await endHome(t);
  });

  testWidgets('interrupted: ring kept, pause glyph, only spend numbers', (
    t,
  ) async {
    final w = FakeWrapper()
      ..sessions = [
        sessionRow('a', {
          'analysis': {
            'state': 'interrupted',
            'stage': 2,
            'done': 12,
            'total': 40,
            'progress': 0.43,
            'tokens': {'in': 900, 'out': 100},
          },
        }),
      ];
    await pumpHome(t, w);
    expect(ring(t).value, closeTo(0.43, 1e-9));
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.text('1 000'), findsOneWidget, reason: 'token total');
    expect(label('items'), findsNothing);
    expect(label('analysis interrupted'), findsOneWidget);
    await endHome(t);
  });
}
