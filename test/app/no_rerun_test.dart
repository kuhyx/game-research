import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_wrapper.dart';
import 'home_helpers.dart';

void main() {
  // Jobs resume by themselves (game-research-resume.timer), so no session
  // row offers a manual rerun, whatever state its job is in.
  testWidgets('no session row has a rerun control', (t) async {
    final w = FakeWrapper()
      ..sessions = [
        for (final (id, state) in [
          ('a', 'running'),
          ('b', 'done'),
          ('c', 'failed'),
          ('d', 'waiting'),
        ])
          sessionRow(id, {
            'draft': '/d.md',
            'analysis': {'state': state, 'progress': 0.5},
          }),
      ];
    await pumpHome(t, w);
    expect(label('draft a'), findsOneWidget);
    expect(label('rerun'), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    await endHome(t);
  });
}
