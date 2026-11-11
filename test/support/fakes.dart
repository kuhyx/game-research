/// Shared fakes: no test starts a real process, plays a sound or opens a
/// window. Every process goes through [FakeSys], which implements the `Sys`
/// seam and records each call.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';

/// A scratch directory removed after the test.
Directory tempDir([String prefix = 'gr_test_']) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// A [Config] pointing everything at [root]: private display, no `:0`.
Config testConfig(Directory root, {Map<String, String> extra = const {}}) =>
    Config.fromEnv({
      'HOME': root.path,
      'GAME_RESEARCH_TEST': '1',
      'GAME_RESEARCH_DISPLAY': ':99',
      'GAME_RESEARCH_DATA': '${root.path}/data',
      'GAME_RESEARCH_STEAM_ROOT': '${root.path}/steam',
      'GAME_RESEARCH_SRC': '${root.path}/src',
      'GAME_RESEARCH_TARGET': '${root.path}/src/cleanup-plate',
      'GAME_RESEARCH_I3_CONFIG': '${root.path}/no-i3-config',
      'GAME_RESEARCH_AUDIO': 'lavfi',
      'GAME_RESEARCH_TICK_CMD': 'faketick',
      'GAME_RESEARCH_ANALYZE': 'inline',
      'GAME_RESEARCH_PORT': '18999',
      ...extra,
    }, cwd: root.path);

/// A process that never runs: stdout/stderr are scripted, stdin is captured.
class FakeProcess implements Process {
  /// A finished process when [exit] is given, else one that runs until
  /// killed by a signal in [exitOn].
  new({
    int? exit,
    String stdoutText = '',
    String stderrText = '',
    this.exitOn = const {ProcessSignal.sigint, ProcessSignal.sigterm},
  }) {
    if (stdoutText.isNotEmpty) _out.add(utf8.encode(stdoutText));
    if (stderrText.isNotEmpty) _err.add(utf8.encode(stderrText));
    _stdinSink = IOSink(_in);
    _in.stream.listen(_stdinBytes.addAll);
    if (exit != null) _finish(exit);
  }

  /// Signals that make it exit.
  final Set<ProcessSignal> exitOn;

  final _out = StreamController<List<int>>();
  final _err = StreamController<List<int>>();
  final _in = StreamController<List<int>>();
  final _stdinBytes = <int>[];
  final _exit = Completer<int>();
  late final IOSink _stdinSink;

  /// Every signal sent with `kill`.
  final signals = <ProcessSignal>[];

  /// Everything written to stdin.
  String get stdinText => utf8.decode(_stdinBytes);

  /// Whether the process exited.
  bool get finished => _exit.isCompleted;

  void _finish(int code) {
    if (_exit.isCompleted) return;
    unawaited(_out.close());
    unawaited(_err.close());
    _exit.complete(code);
  }

  /// Exits with [code] as if the program ended by itself.
  void exitWith(int code) => _finish(code);

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  @override
  IOSink get stdin => _stdinSink;

  @override
  Stream<List<int>> get stdout => _out.stream;

  @override
  Stream<List<int>> get stderr => _err.stream;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (exitOn.contains(signal)) _finish(-signal.signalNumber);
    return true;
  }
}

/// One recorded call to the seam.
class Call {
  /// Records a call.
  const new(
    this.exe,
    this.args, {
    this.env,
    this.cwd,
    this.mode,
    this.isStart = false,
  });

  /// Program.
  final String exe;

  /// Arguments.
  final List<String> args;

  /// Environment given.
  final Map<String, String>? env;

  /// Working directory given.
  final String? cwd;

  /// Start mode (start calls only).
  final ProcessStartMode? mode;

  /// Whether it was `start` (else `run`).
  final bool isStart;

  /// `exe arg arg`, for matching.
  String get line => [exe, ...args].join(' ');

  @override
  String toString() => line;
}

/// The seam over scripted answers.
class FakeSys {
  /// Creates the fake; the clock starts at [now] and moves [step] per read.
  new({this.now = 1700000000, this.step = 1});

  /// Next clock value.
  double now;

  /// Added after each clock read.
  double step;

  /// Every call in order.
  final calls = <Call>[];

  /// Every process handed out by `start`.
  final started = <FakeProcess>[];

  /// Answers a `run`; null = success with empty output.
  ProcessResult? Function(Call call)? onRun;

  /// Answers a `start`; null = a finished process. May throw.
  FutureOr<FakeProcess?> Function(Call call)? onStart;

  /// The seam to hand to the code under test.
  late final Sys sys = Sys(run: _run, start: _start, nowUnix: _clock);

  double _clock() {
    final v = now;
    now += step;
    return v;
  }

  Future<ProcessResult> _run(
    String exe,
    List<String> args, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    final call = Call(exe, args, env: environment, cwd: workingDirectory);
    calls.add(call);
    return onRun?.call(call) ?? ProcessResult(1, 0, '', '');
  }

  Future<Process> _start(
    String exe,
    List<String> args, {
    Map<String, String>? environment,
    String? workingDirectory,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    final call = Call(
      exe,
      args,
      env: environment,
      cwd: workingDirectory,
      mode: mode,
      isStart: true,
    );
    calls.add(call);
    final process = await onStart?.call(call) ?? FakeProcess(exit: 0);
    started.add(process);
    return process;
  }

  /// Calls to [exe], in order.
  List<Call> of(String exe) => [
    for (final c in calls)
      if (c.exe == exe) c,
  ];
}

/// A successful result with [stdout].
ProcessResult ok([String stdout = '']) => ProcessResult(1, 0, stdout, '');

/// A failed result with [stderr].
ProcessResult bad([String stderr = '', int code = 1]) =>
    ProcessResult(1, code, '', stderr);

/// Lets queued microtasks and zero-delay timers run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));
