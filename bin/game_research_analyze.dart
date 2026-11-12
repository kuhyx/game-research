/// `game_research_analyze <session dir> [--force]`, `--finish <slug>` or
/// `--resume-all`: the analysis jobs. The wrapper starts the first two as
/// `systemd-run --user --collect` units; a systemd user timer runs the third.
///
/// Only wiring: the stages live in `lib/analysis/`, the command line in
/// `lib/analysis/cli.dart`. Exit 0 done, 1 a stage failed (see
/// `analysis/status.json`), 2 bad arguments, 3 already running, 4 waiting.
library;

import 'dart:io';

import 'package:game_research/analysis/cli.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final config = Config.fromEnv(
    Platform.environment,
    cwd: Directory.current.path,
  );
  final client = http.Client();
  try {
    exitCode = await analyzeMain(args, config, const Sys(), client);
  } finally {
    client.close();
  }
}
