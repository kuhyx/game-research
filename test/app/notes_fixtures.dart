import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/notes_panel.dart';

import 'fake_wrapper.dart';

const stampA = '20261110-200000-one';
const stampB = '20261111-210000-one';

Map<String, Object?> marker(
  String session,
  int i,
  String tag,
  String time,
  String note, {
  bool still = true,
}) => {
  'session': session,
  'i': i,
  'tag': tag,
  'time': time,
  'note': note,
  'line': '$tag $time $note',
  'still': still,
};

/// Two parts: two sessions in the first, an unknown tag in the second.
List<Map<String, Object?>> twoParts({bool still = true}) => [
  {
    'n': 1,
    'of': 2,
    'text': '**One** · my notes 1/2',
    'markers': [
      marker(stampA, 1, 'good', '0:01:05', 'nice shelf', still: still),
      marker(stampA, 2, 'bad', '0:01:30', '', still: still),
      marker(stampB, 1, 'confusing', '1:02:03', 'what now', still: still),
    ],
  },
  {
    'n': 2,
    'of': 2,
    'text': '**One** · my notes 2/2',
    'markers': [marker(stampB, 2, 'weird', '1:03:00', 'odd', still: still)],
  },
];

/// Opens the notes of game 1 at 4K.
Future<void> openNotes(
  WidgetTester t,
  FakeWrapper w, {
  VoidCallback? onClose,
  Size size = const Size(3840, 2160),
  double dpr = 2,
  Duration pollEvery = const Duration(seconds: 2),
  int maxPolls = 3,
}) async {
  t.view
    ..physicalSize = size
    ..devicePixelRatio = dpr;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotesPanel(
          api: w.api(),
          appid: 1,
          onClose: onClose ?? () {},
          pollEvery: pollEvery,
          maxPolls: maxPolls,
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

/// Ends the test's widget tree (cancels the poll timer).
Future<void> endNotes(WidgetTester t) => t.pumpWidget(const SizedBox());
