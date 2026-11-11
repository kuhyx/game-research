/// `game-research`: serve the web build and the session API, open the
/// GUI in a Chrome app window.
///
/// Only wiring: decisions live in `lib/desktop/launcher.dart`. Build the
/// page first with `flutter build web --release --no-web-resources-cdn`.
/// `--serve-only` skips the window; `--window-only` skips serving.
library;

import 'dart:io';

import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/launcher.dart';
import 'package:game_research/desktop/sys.dart';

Future<void> main(List<String> args) async {
  final config = Config.fromEnv(
    Platform.environment,
    cwd: Directory.current.path,
  );
  exitCode = await runDesktop(args, config, const Sys());
}
