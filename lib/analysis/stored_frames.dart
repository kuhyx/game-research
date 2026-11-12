/// The frame list an earlier run of stage 1 chose.
///
/// Frame files and captions are named by index (`f_0001.png`), so a resumed
/// job keeps the stored list: resampling (the sampling rules changed since,
/// e.g. the black lead-in) would relabel every frame and caption.
library;

import 'dart:io';

import 'package:game_research/core/safe_json.dart';
import 'package:game_research/core/sampling.dart';
import 'package:path/path.dart' as p;

/// `frames.json` under analysis folder [analysisDir], or null when it is
/// missing, empty or unreadable (then the frames are sampled afresh).
List<SampleFrame>? storedFrames(String analysisDir) {
  final stored = readJson(File(p.join(analysisDir, 'frames.json')));
  if (stored is! List) return null;
  try {
    final frames = [
      for (final j in stored) SampleFrame.fromJson(j as Map<String, Object?>),
    ];
    return frames.isEmpty ? null : frames;
  } on Object {
    return null;
  }
}
