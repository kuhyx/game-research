/// The operating-system seam: running and starting processes, the clock.
///
/// Every component takes a [Sys] so tests swap in fakes and never start
/// ffmpeg, sxhkd, dmenu, Steam or a sound on kuhy's machine.
library;

import 'dart:io';

/// Runs a command to completion.
typedef RunFn = Future<ProcessResult> Function(
  String exe,
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
});

/// Starts a long-lived command.
typedef StartFn = Future<Process> Function(
  String exe,
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
  ProcessStartMode mode,
});

/// The seam.
class Sys {
  /// Creates a seam; defaults are the real system.
  const new({this.run = _run, this.start = _start, this.nowUnix = unixNow});

  /// Runs to completion.
  final RunFn run;

  /// Starts.
  final StartFn start;

  /// Wall clock, unix seconds.
  final double Function() nowUnix;
}

/// The wall clock in unix seconds, microsecond resolution.
double unixNow() => DateTime.now().microsecondsSinceEpoch / 1e6;

// coverage:ignore-start
// The real process calls; every test replaces them.
Future<ProcessResult> _run(
  String exe,
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
}) => Process.run(
  exe,
  args,
  environment: environment,
  workingDirectory: workingDirectory,
);

Future<Process> _start(
  String exe,
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
  ProcessStartMode mode = ProcessStartMode.normal,
}) => Process.start(
  exe,
  args,
  environment: environment,
  workingDirectory: workingDirectory,
  mode: mode,
);
// coverage:ignore-end
