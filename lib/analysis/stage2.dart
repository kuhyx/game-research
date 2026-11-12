/// Stage 2: captions for the frames stage 3 will look at, [kCaptionBatch]
/// frames per model call through the tier chain.
///
/// `captions.jsonl` gets one line per captioned frame as it happens, so a
/// rerun captions only the frames that are still missing. A frame no tier
/// could caption is not written; the stage then fails closed after the batch
/// that could not caption it (no point hammering a rate-limited chain).
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/analysis/stage1.dart';
import 'package:game_research/core/caption_batch.dart';
import 'package:game_research/core/captions.dart';
import 'package:game_research/core/safe_json.dart';
import 'package:game_research/core/sampling.dart';
import 'package:path/path.dart' as p;

/// Runs stage 2 on session folder [dir].
class Stage2 {
  /// Creates the stage over [tiers] (in fallback order).
  const new(this.dir, this.tiers, {this.gate = openGate});

  /// Session folder.
  final String dir;

  /// Caption tiers.
  final List<CaptionTier> tiers;

  /// Awaited before each caption: holds the job while a recording runs.
  final Gate gate;

  File get _captions => File(p.join(dir, 'analysis', 'captions.jsonl'));

  /// The intact rows; a torn or NUL-filled line (power cut) is dropped.
  JsonlRead _load() => readJsonl(
    _captions,
    accept: (row) {
      CaptionRecord.fromJson(row);
      return true;
    },
  );

  /// Frames already captioned (by file name): a frame whose line is torn is
  /// not captioned.
  Set<String> done() => {
    for (final row in _load().rows) row['frame']! as String,
  };

  /// Rewrites `captions.jsonl` with only its intact rows (tmp + rename) when
  /// a power cut damaged it, so the next append starts on a clean line.
  /// Returns how many lines were dropped.
  int repair() {
    final read = _load();
    if (read.clean) return 0;
    writeJsonlAtomic(_captions, read.rows);
    return read.skipped;
  }

  /// Captions every missing frame. Returns the frames no tier captioned.
  Future<List<String>> run(List<SampleFrame> frames, Progress progress) async {
    repair();
    final have = done();
    final todo = [
      for (final f in frames)
        if (!have.contains(f.file)) f,
    ];
    var captioned = frames.length - todo.length;
    progress(captioned, frames.length);
    for (var i = 0; i < todo.length; i += kCaptionBatch) {
      final batch = todo.skip(i).take(kCaptionBatch).toList();
      await gate();
      final records = await captionFrames(tiers, [
        for (final f in batch)
          FrameRef(
            file: f.file,
            path: p.join(dir, 'analysis', 'frames', f.file),
            t: f.t,
          ),
      ]);
      final failed = <String>[];
      for (final rec in records) {
        if (rec.ok) {
          _captions.writeAsStringSync(
            '${jsonEncode(rec.toJson())}\n',
            mode: FileMode.append,
            flush: true,
          );
          captioned++;
        } else {
          failed.add('${rec.frame} (${rec.skipped.join('; ')})');
        }
      }
      progress(captioned, frames.length);
      if (failed.isNotEmpty) return failed;
    }
    return const [];
  }
}
