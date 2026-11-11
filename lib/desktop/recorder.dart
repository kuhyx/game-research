/// Starting, stopping and finishing the ffmpeg recording.
library;

import 'dart:async';
import 'dart:io';

import 'package:game_research/core/chapters.dart';
import 'package:game_research/core/ffmpeg_parse.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/recorder_args.dart';
import 'package:game_research/core/xrandr.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// Raised when a session cannot start; the GUI shows the failure.
class StartError implements Exception {
  /// Creates the error.
  const new(this.message);

  /// Why.
  final String message;

  @override
  String toString() => 'StartError: $message';
}

/// One running ffmpeg.
class Recording {
  /// Wraps [process].
  new(this.process, {this.stopTimeout = const Duration(seconds: 20)});

  /// The ffmpeg process.
  final Process process;

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
    }
  }
}

/// The recorder.
class Recorder {
  /// Creates a recorder.
  const new(this.config, this.sys);

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  Map<String, String> get _xEnv => {'DISPLAY': config.display};

  /// The output to grab: an explicit geometry, else the named RandR output.
  /// Null when it is not connected: never grab a different monitor.
  Future<Output?> resolveOutput() async {
    final fixed = parseGeometry(config.output);
    if (fixed != null) return fixed;
    final r = await sys.run('xrandr', ['--query'], environment: _xEnv);
    if (r.exitCode != 0) return null;
    return findOutput(parseXrandr('${r.stdout}'), config.output);
  }

  /// The best encoder that really encodes a frame here, or null.
  Future<String?> probeEncoder() async {
    final usable = <String>{};
    for (final codec in const [kNvencHevc, kNvencH264, kX264]) {
      final args = encoderProbeArgs(codec);
      final r = await sys.run(args.first, args.sublist(1));
      if (r.exitCode == 0) {
        usable.add(codec);
        break; // the list is in preference order
      }
    }
    return pickEncoder(usable);
  }

  /// Starts ffmpeg for [spec]; its stderr goes to `ffmpeg.log` beside it.
  Future<Recording> start(RecordSpec spec) async {
    final args = ffmpegRecordArgs(spec);
    final process = await sys.start(
      args.first,
      args.sublist(1),
      environment: _xEnv,
    );
    final log = File(p.join(p.dirname(spec.out), 'ffmpeg.log'));
    unawaited(process.stderr.pipe(log.openWrite(mode: FileMode.append)));
    unawaited(process.stdout.drain<void>());
    return Recording(process);
  }

  /// The recording's length in seconds (ffprobe), or null when unreadable.
  Future<double?> duration(String video) async {
    final r = await sys.run('ffprobe', [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'json',
      video,
    ]);
    if (r.exitCode != 0) return null;
    try {
      return parseDuration('${r.stdout}');
    } on FormatException {
      return null;
    }
  }

  /// Remuxes [video] with [markers] as chapters (streams copied). Returns
  /// the duration, or throws when ffprobe or ffmpeg fails.
  Future<double> embedChapters(String video, List<Marker> markers) async {
    final length = await duration(video);
    if (length == null) throw StateError('ffprobe cannot read $video');
    if (markers.isEmpty) return length;
    final meta = File(p.setExtension(video, '.ffmeta'))
      ..writeAsStringSync(chaptersFfmetadata(markers, length));
    final tmp = p.setExtension(video, '.chapters.mkv');
    final args = embedChaptersArgs(video, meta.path, tmp);
    final r = await sys.run(args.first, args.sublist(1));
    meta.deleteSync();
    if (r.exitCode != 0) {
      throw StateError('chapter remux failed: ${r.stderr}');
    }
    File(tmp).renameSync(video);
    return length;
  }
}
