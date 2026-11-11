/// Stage 2: one caption per sampled frame through the tier chain.
///
/// `captions.jsonl` gets one line per captioned frame as it happens, so a
/// rerun captions only the frames that are still missing. A frame no tier
/// could caption is not written; the stage then fails closed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/analysis/stage1.dart';
import 'package:game_research/core/captions.dart';
import 'package:game_research/core/sampling.dart';
import 'package:path/path.dart' as p;

/// Runs stage 2 on session folder [dir].
class Stage2 {
  /// Creates the stage over [tiers] (in fallback order).
  const new(this.dir, this.tiers);

  /// Session folder.
  final String dir;

  /// Caption tiers.
  final List<CaptionTier> tiers;

  File get _captions => File(p.join(dir, 'analysis', 'captions.jsonl'));

  /// Frames already captioned (by file name).
  Set<String> done() {
    if (!_captions.existsSync()) return {};
    return {
      for (final line in const LineSplitter().convert(
        _captions.readAsStringSync(),
      ))
        if (line.trim().isNotEmpty)
          CaptionRecord.fromJson(jsonDecode(line) as Map<String, Object?>)
              .frame,
    };
  }

  /// Captions every missing frame. Returns the frames no tier captioned.
  Future<List<String>> run(List<SampleFrame> frames, Progress progress) async {
    final have = done();
    final failed = <String>[];
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i];
      if (!have.contains(f.file)) {
        final rec = await captionWithFallback(
          tiers,
          p.join(dir, 'analysis', 'frames', f.file),
          t: f.t,
        );
        if (rec.ok) {
          final line = jsonEncode({...rec.toJson(), 'frame': f.file});
          _captions.writeAsStringSync('$line\n', mode: FileMode.append);
        } else {
          failed.add('${f.file} (${rec.skipped.join('; ')})');
        }
      }
      progress(i + 1, frames.length);
    }
    return failed;
  }
}
