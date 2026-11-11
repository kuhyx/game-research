/// game-research GUI: Flutter web in a Chrome app window, served by the
/// local wrapper (`bin/game_research_desktop.dart`), which owns ffmpeg, the
/// files, the hotkeys and the analysis jobs.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/home_screen.dart';
import 'package:http/http.dart' as http;

// coverage:ignore-start
// The browser entry point: tests build GameResearchApp directly.
void main() {
  runApp(GameResearchApp(api: ResearchApi(Uri.base, http.Client())));
}
// coverage:ignore-end

/// The app.
class GameResearchApp extends StatelessWidget {
  /// Creates the app over [api].
  const new({required this.api, super.key});

  /// The wrapper client.
  final ResearchApi api;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildDarkTheme(),
    home: HomeScreen(api: api),
  );
}
