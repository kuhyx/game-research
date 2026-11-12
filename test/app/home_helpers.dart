import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/home_screen.dart';

import 'fake_wrapper.dart';

Future<void> pumpHome(
  WidgetTester t,
  FakeWrapper w, {
  bool autostart = false,
}) async {
  t.view
    ..physicalSize = const Size(2560, 1440)
    ..devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: HomeScreen(api: w.api(), now: () => 165, autostart: autostart),
    ),
  );
  await t.pump();
  await t.pump();
}

Future<void> endHome(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

Finder label(String l) => find.bySemanticsLabel(RegExp('^${RegExp.escape(l)}'));

Map<String, Object?> sessionRow(String id, Map<String, Object?> extra) => {
  'id': id,
  'appid': 2,
  'started_unix': 0,
  'duration_s': 60,
  ...extra,
};
