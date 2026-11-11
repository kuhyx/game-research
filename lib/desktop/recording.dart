/// One running recorder process, and the error of a start that failed.
library;

import 'dart:async';
import 'dart:io';

import 'package:game_research/core/recorder_args.dart';

/// Raised when a session cannot start; the GUI shows the failure.
class StartError implements Exception {
  /// Creates the error.
  const new(this.message);

  /// Why.
  final String message;

  @override
  String toString() => 'StartError: $message';
}

/// One running recorder process.
class Recording {
  /// Wraps [process], which writes [out] with [codec].
  new(
    this.process, {
    this.stopTimeout = const Duration(seconds: 20),
    this.codec = kNvencHevc,
    this.out = '',
    this.onStop,
  });

  /// The recorder process.
  final Process process;

  /// `gpu-screen-recorder`, or the ffmpeg encoder.
  final String codec;

  /// The video file.
  final String out;

  /// Runs once the process has exited after [stop].
  final void Function()? onStop;

  /// How long ffmpeg gets to finalise after SIGINT before SIGKILL.
  final Duration stopTimeout;

  /// Completes when ffmpeg exits, for any reason.
  Future<int> get exited => process.exitCode;

  /// SIGINT (ffmpeg writes the Matroska cues and exits), then waits.
  Future<int> stop() async {
    process.kill(ProcessSignal.sigint);
    try {
      return await process.exitCode.timeout(stopTimeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return await process.exitCode;
    } finally {
      onStop?.call();
    }
  }
}
