/// Stage 1, ffmpeg only: scene cuts, still stretches, sampled frames, a
/// 10 s clip per marker and contact sheets. Every output is skipped when it
/// already exists, so a rerun resumes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/ffmpeg_parse.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/sampling.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// Reports progress: [done] of [total] items.
typedef Progress = void Function(int done, int total);

/// Completes when the job may do its next heavy step.
typedef Gate = Future<void> Function();

/// A gate that never holds.
Future<void> openGate() async {}

/// Half the clip around a marker, seconds.
const kClipHalfS = 5.0;

/// The scene-change threshold of ffmpeg's `scene` score.
const kSceneThreshold = 0.3;

/// Runs stage 1 on session folder [dir].
class Stage1 {
  /// Creates the stage; [stillS] is the shortest still stretch reported.
  const new(this.dir, this.sys, {this.stillS = 20, this.gate = openGate});

  /// Session folder.
  final String dir;

  /// OS seam.
  final Sys sys;

  /// Shortest no-motion stretch, seconds.
  final double stillS;

  /// Awaited before each heavy step: holds the job while a recording runs.
  final Gate gate;

  String get _out => p.join(dir, 'analysis');
  String get _video => p.join(dir, 'recording.mkv');

  Future<ProcessResult> _ffmpeg(List<String> args) async {
    final r = await sys.run('ffmpeg', ['-hide_banner', '-nostdin', ...args]);
    if (r.exitCode != 0) {
      throw StateError('ffmpeg ${args.take(6).join(' ')}: ${r.stderr}');
    }
    return r;
  }

  /// One decode pass, downscaled: freezedetect logs still stretches and
  /// select + showinfo log scene cuts. Writes scenes.json and still.jsonl.
  Future<(List<double>, List<Span>)> detect(double durationS) async {
    final scenesFile = File(p.join(_out, 'scenes.json'));
    final stillFile = File(p.join(_out, 'still.jsonl'));
    if (scenesFile.existsSync() && stillFile.existsSync()) {
      final scenes = (jsonDecode(scenesFile.readAsStringSync()) as List)
          .cast<num>()
          .map((n) => n.toDouble())
          .toList();
      final spans = const LineSplitter()
          .convert(stillFile.readAsStringSync())
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, Object?>)
          .map(
            (m) => Span(
              (m['start_s']! as num).toDouble(),
              (m['end_s']! as num).toDouble(),
            ),
          )
          .toList();
      return (scenes, spans);
    }
    final filter =
        'scale=320:-2,freezedetect=n=-50dB:d=${stillS.toStringAsFixed(1)},'
        "select='gt(scene,$kSceneThreshold)',showinfo";
    final r = await _ffmpeg([
      '-v',
      'info',
      '-i',
      _video,
      '-an',
      '-vf',
      filter,
      '-f',
      'null',
      '-',
    ]);
    final log = '${r.stderr}';
    final scenes = parseSceneCuts(log);
    final spans = parseFreezes(log, durationS: durationS);
    scenesFile.writeAsStringSync(jsonEncode(scenes));
    stillFile.writeAsStringSync(
      spans.map((s) => '${jsonEncode(s.toJson())}\n').join(),
    );
    return (scenes, spans);
  }

  /// Extracts [frames] (PNG, at most 1280 px wide), skipping existing ones.
  Future<void> extractFrames(
    List<SampleFrame> frames,
    Progress progress,
  ) async {
    final dir = Directory(p.join(_out, 'frames'))..createSync(recursive: true);
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i];
      final out = p.join(dir.path, f.file);
      if (!File(out).existsSync()) {
        await gate();
        await _ffmpeg([
          '-v',
          'error',
          '-ss',
          f.t.toStringAsFixed(3),
          '-i',
          _video,
          '-frames:v',
          '1',
          '-vf',
          "scale='min(1280,iw)':-2",
          '-y',
          out,
        ]);
      }
      progress(i + 1, frames.length);
    }
  }

  /// A 10 s clip around each marker, streams copied (no re-encode).
  Future<List<String>> clips(List<Marker> markers) async {
    final dir = Directory(p.join(_out, 'clips'))..createSync(recursive: true);
    final names = <String>[];
    for (var i = 0; i < markers.length; i++) {
      final m = markers[i];
      final name = 'm_${(i + 1).toString().padLeft(2, '0')}_${m.tag.name}.mkv';
      names.add(name);
      final out = p.join(dir.path, name);
      if (File(out).existsSync()) continue;
      await gate();
      final start = m.offsetS - kClipHalfS < 0 ? 0.0 : m.offsetS - kClipHalfS;
      await _ffmpeg([
        '-v',
        'error',
        '-ss',
        start.toStringAsFixed(3),
        '-i',
        _video,
        '-t',
        (2 * kClipHalfS).toStringAsFixed(1),
        '-map',
        '0',
        '-c',
        'copy',
        '-y',
        out,
      ]);
    }
    return names;
  }

  /// Contact sheets of the sampled frames, 4x4 per sheet.
  Future<void> contactSheets() async {
    final dir = Directory(p.join(_out, 'contact'))..createSync(recursive: true);
    if (dir.listSync().isNotEmpty) return;
    await _ffmpeg([
      '-v',
      'error',
      '-framerate',
      '1',
      '-i',
      p.join(_out, 'frames', 'f_%04d.png'),
      '-vf',
      'scale=480:-2,tile=4x4:padding=4:margin=4',
      '-y',
      p.join(dir.path, 'sheet_%03d.png'),
    ]);
  }

  /// Runs every step; [durationS] and [markers] come from the session.
  Future<List<SampleFrame>> run({
    required double durationS,
    required List<Marker> markers,
    required Progress progress,
  }) async {
    Directory(_out).createSync(recursive: true);
    await gate();
    final (scenes, _) = await detect(durationS);
    final frames = sampleFrames(
      scenes: scenes,
      markers: markers,
      durationS: durationS,
    );
    File(p.join(_out, 'frames.json'))
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(frames));
    final total = frames.length + 2;
    await extractFrames(frames, (d, _) => progress(d, total));
    await clips(markers);
    progress(frames.length + 1, total);
    await gate();
    await contactSheets();
    progress(total, total);
    return frames;
  }
}
