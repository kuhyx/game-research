/// Wiring of the wrapper process, kept out of `bin/` so it is testable.
///
/// The server outlives the browser on purpose: Chrome exits at once when it
/// hands the URL to an instance that already owns the profile, so an early
/// exit is a handoff, not "the window was closed".
library;

import 'dart:io';

import 'package:game_research/desktop/browser.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/session_controller.dart';
import 'package:game_research/desktop/session_parts.dart';
import 'package:game_research/desktop/steam_library.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:game_research/desktop/wrapper_server.dart';
import 'package:path/path.dart' as p;

/// Builds the controller from [config] and [sys].
SessionController buildController(Config config, Sys sys) =>
    SessionController(SessionParts.real(config, sys));

/// Where the web build is: `build/web` of the checkout.
String webRootOf(Config config) => p.join(config.repo, 'build', 'web');

/// Starts the server on [Config.port] (0 in tests); returns it.
Future<WrapperServer> serve(Config config, Sys sys, {int? port}) async {
  final controller = buildController(config, sys);
  // A wrapper that crashed mid-session may have left its keys grabbed.
  await controller.parts.hotkeys.stop();
  final server = WrapperServer(
    webRoot: webRootOf(config),
    controller: controller,
    library: SteamLibrary(config.steamRoot),
    open: (path) async {
      await sys.start('xdg-open', [path], mode: ProcessStartMode.detached);
    },
  );
  await server.start(port ?? config.port);
  return server;
}

/// Runs the wrapper: serve (unless `--window-only`), then open the window
/// (unless `--serve-only`), then keep serving.
Future<int> runDesktop(
  List<String> args,
  Config config,
  Sys sys, {
  String Function() browserFinder = findBrowser,
  Future<void> Function() hold = _forever,
  void Function(String) err = _stderr,
}) async {
  var serving = false;
  if (!args.contains('--window-only')) {
    try {
      await serve(config, sys);
      serving = true;
    } on SocketException {
      err('game-research: already running on :${config.port}');
    }
  }
  if (!args.contains('--serve-only')) {
    final browser = browserFinder();
    if (browser.isEmpty) {
      err('game-research: no Chrome-family browser; set GAME_RESEARCH_BROWSER');
      if (!serving) return 1;
      await hold();
      return 0;
    }
    final scale = await detectScale(
      sys,
      override: config.env['GAME_RESEARCH_SCALE'],
    );
    final process = await sys.start(
      browser,
      browserArgs(config.home, port: config.port, scale: scale),
      environment: {'DISPLAY': config.display},
    );
    await process.exitCode;
  }
  if (serving) await hold();
  return 0;
}

// coverage:ignore-start
// Production defaults that tests replace: wait a year so the wrapper keeps
// serving a handed-off window, and write to stderr.
Future<void> _forever() => Future<void>.delayed(const Duration(days: 365));

void _stderr(String line) => stderr.writeln(line);
// coverage:ignore-end
