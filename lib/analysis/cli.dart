/// The analyzer's command line:
///
///     game_research_analyze <session dir> [--force]   one session's job
///     game_research_analyze --finish <slug>           merge a game's drafts
///     game_research_analyze --resume-all              what the timer runs
///
/// Exit codes ([JobExit]): 0 done, 1 a stage failed, 2 bad arguments, 3 the
/// job already runs, 4 waiting (queued, or a usage limit). After a job ends
/// the machine is free, so the next waiting job is started in the same
/// process (the queue drains without waiting for the timer).
library;

import 'dart:io';

import 'package:game_research/analysis/finish.dart';
import 'package:game_research/analysis/job.dart';
import 'package:game_research/analysis/resume.dart';
import 'package:game_research/analysis/runner.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:http/http.dart' as http;

/// The usage line.
const kUsage =
    'usage: game_research_analyze <session dir> [--force] | '
    '--finish <slug> | --resume-all';

/// Runs the command [args] and returns the exit code.
Future<int> analyzeMain(
  List<String> args,
  Config config,
  Sys sys,
  http.Client client, {
  Duration recordingPoll = const Duration(seconds: 5),
  IOSink? err,
}) async {
  final sink = err ?? stderr;
  final resume = ResumeAll(config, sys, client, recordingPoll: recordingPoll);
  final flags = args.where((a) => a.startsWith('--')).toSet();
  final words = args.where((a) => !a.startsWith('--')).toList();
  int usage() {
    sink.writeln(kUsage);
    return JobExit.usage;
  }

  if (flags.contains('--resume-all')) {
    if (args.length != 1) return usage();
    return await resume.run();
  }
  final int code;
  if (flags.contains('--finish')) {
    if (words.length != 1 || args.length != 2) return usage();
    code = await FinishRunner(
      words.single,
      config,
      sys,
      recordingPoll: recordingPoll,
    ).run();
  } else {
    if (words.length != 1 || flags.any((f) => f != '--force')) return usage();
    code = await AnalysisRunner(
      words.single,
      config,
      sys,
      client,
      recordingPoll: recordingPoll,
    ).run(force: flags.contains('--force'));
  }
  if (code != JobExit.usage && code != JobExit.running) await resume.run();
  return code;
}
