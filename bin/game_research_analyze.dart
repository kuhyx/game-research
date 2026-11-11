/// `game_research_analyze <session dir> [--force]`: the analysis job the
/// wrapper starts as a `systemd-run --user --collect` unit after Stop.
///
/// Only wiring: the stages live in `lib/analysis/`. Exit 0 done, 1 a stage
/// failed (see `analysis/status.json`), 2 bad arguments, 3 already running.
library;

import 'dart:io';

import 'package:game_research/analysis/runner.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final dirs = args.where((a) => !a.startsWith('--')).toList();
  if (dirs.length != 1) {
    stderr.writeln('usage: game_research_analyze <session dir> [--force]');
    exitCode = 2;
    return;
  }
  final config = Config.fromEnv(
    Platform.environment,
    cwd: Directory.current.path,
  );
  final client = http.Client();
  try {
    exitCode = await AnalysisRunner(
      dirs.single,
      config,
      const Sys(),
      client,
    ).run(force: args.contains('--force'));
  } finally {
    client.close();
  }
}
