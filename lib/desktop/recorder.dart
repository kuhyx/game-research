/// Starting, stopping and finishing the recording: gpu-screen-recorder
/// when it can capture the output, else ffmpeg x11grab.
library;

import 'dart:async';
import 'dart:io';

import 'package:game_research/core/chapters.dart';
import 'package:game_research/core/ffmpeg_parse.dart';
import 'package:game_research/core/gsr_args.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/recorder_args.dart';
import 'package:game_research/core/xrandr.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/recording.dart';
import 'package:game_research/desktop/recording_flag.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

export 'package:game_research/desktop/recording.dart';

/// The recorder.
class Recorder {
  /// Creates a recorder.
  const new(
    this.config,
    this.sys, {
    this.firstFrameTimeout = const Duration(seconds: 2),
    this.poll = const Duration(milliseconds: 50),
  });

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  /// How long gsr gets to write its first frame before x11grab takes over.
  final Duration firstFrameTimeout;

  /// How often the first-frame file is looked for.
  final Duration poll;

  /// Up while a recording runs: the analysis job waits on it.
  RecordingFlag get flag => RecordingFlag(config.dataDir);

  Map<String, String> get _xEnv => {'DISPLAY': config.display};

  /// The output to grab: an explicit `WxH+X+Y`, else the monitor under
  /// [window] (a configured name wins while it exists), else the primary.
  /// Null when xrandr fails or lists no monitor.
  Future<OutputPick?> resolveOutput({Rect? window}) async {
    final fixed = parseGeometry(config.output);
    if (fixed != null) return (output: fixed, why: 'geometry');
    final r = await sys.run('xrandr', ['--listmonitors'], environment: _xEnv);
    if (r.exitCode != 0) return null;
    final monitors = parseMonitors('${r.stdout}');
    return pickOutput(monitors, window: window, pin: config.output);
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

  /// [kGsr] when gpu-screen-recorder lists [output] (CAPTURE `auto` or
  /// `gsr`), else the best ffmpeg encoder (`auto`, `x11grab`); null when
  /// nothing can record.
  Future<String?> probeCapture(Output output) async {
    if (config.capture != 'x11grab') {
      final r = await sys.run(
        gsrProbeArgs.first,
        gsrProbeArgs.sublist(1),
        environment: _xEnv,
      );
      if (r.exitCode == 0 && gsrLists('${r.stdout}', output)) return kGsr;
      if (config.capture == 'gsr') return null;
    }
    return await probeEncoder();
  }

  Future<Process> _spawn(List<String> args, String out, String logName) async {
    final process = await sys.start(
      args.first,
      args.sublist(1),
      environment: _xEnv,
    );
    final log = File(p.join(p.dirname(out), logName));
    unawaited(process.stderr.pipe(log.openWrite(mode: FileMode.append)));
    unawaited(process.stdout.drain<void>());
    return process;
  }

  /// Starts gsr; null when it dies before writing its first-frame time or
  /// before [firstFrameTimeout] passes. Alive past it counts as recording:
  /// the time file may only appear at exit, and [finish] requires it.
  Future<Process?> _startGsr(RecordSpec spec) async {
    final process = await _spawn(gsrRecordArgs(spec), spec.out, 'gsr.log');
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    final ts = File(gsrTsPath(spec.out));
    final deadline = DateTime.now().add(firstFrameTimeout);
    while (!exited && DateTime.now().isBefore(deadline)) {
      if (ts.existsSync()) return process;
      await Future<void>.delayed(poll);
    }
    return exited ? null : process;
  }

  /// Starts the recorder for [spec] and raises [flag]. A gsr spec that
  /// yields no frame falls back to x11grab with the best ffmpeg encoder;
  /// the returned [Recording.codec] says which ran. Stderr goes to
  /// `gsr.log` / `ffmpeg.log` beside the video.
  Future<Recording> start(RecordSpec spec) async {
    flag.raise();
    try {
      var s = spec;
      if (s.codec == kGsr) {
        final gsr = await _startGsr(s);
        if (gsr != null) {
          return Recording(gsr, codec: kGsr, out: s.out, onStop: flag.lower);
        }
        final codec = await probeEncoder();
        if (codec == null) throw const StartError('no working video encoder');
        s = RecordSpec(
          output: s.output,
          display: s.display,
          fps: s.fps,
          t0Unix: s.t0Unix,
          out: s.out,
          audio: s.audio,
          codec: codec,
        );
      }
      final process = await _spawn(ffmpegRecordArgs(s), s.out, 'ffmpeg.log');
      return Recording(process, codec: s.codec, out: s.out, onStop: flag.lower);
    } on Object {
      flag.lower();
      rethrow;
    }
  }

  /// Finishes [rec] started at [t0]: chapters for [markers], and for gsr
  /// the shift that puts t0 at file time 0. Returns the duration; throws
  /// when the video or gsr's first-frame time is unreadable.
  Future<double> finish(Recording rec, List<Marker> markers, double t0) async {
    var shift = 0.0;
    if (rec.codec == kGsr) {
      final ts = File(gsrTsPath(rec.out));
      final first = ts.existsSync()
          ? parseFirstFrameTs(ts.readAsStringSync())
          : null;
      if (first == null) throw StateError('gsr wrote no first-frame time');
      shift = first - t0;
    }
    return await embedChapters(rec.out, markers, shiftS: shift);
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

  /// Remuxes [video] with [markers] as chapters (streams copied), moved
  /// later by [shiftS]. Returns the duration on the shifted timeline, or
  /// throws when ffprobe or ffmpeg fails.
  Future<double> embedChapters(
    String video,
    List<Marker> markers, {
    double shiftS = 0,
  }) async {
    final probed = await duration(video);
    if (probed == null) throw StateError('ffprobe cannot read $video');
    final length = probed + shiftS;
    if (markers.isEmpty && shiftS == 0) return length;
    final meta = File(p.setExtension(video, '.ffmeta'))
      ..writeAsStringSync(chaptersFfmetadata(markers, length));
    final tmp = p.setExtension(video, '.chapters.mkv');
    final args = embedChaptersArgs(video, meta.path, tmp, shiftS: shiftS);
    final r = await sys.run(args.first, args.sublist(1));
    meta.deleteSync();
    if (r.exitCode != 0) {
      throw StateError('chapter remux failed: ${r.stderr}');
    }
    File(tmp).renameSync(video);
    return length;
  }
}
