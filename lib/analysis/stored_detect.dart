/// The scene cuts and still stretches an earlier run of stage 1 detected.
library;

import 'dart:io';

import 'package:game_research/core/ffmpeg_parse.dart';
import 'package:game_research/core/safe_json.dart';
import 'package:path/path.dart' as p;

Span _span(Map<String, Object?> m) =>
    Span((m['start_s']! as num).toDouble(), (m['end_s']! as num).toDouble());

/// `scenes.json` and `still.jsonl` under [outDir]; null when either is
/// missing or damaged (the decode pass then runs again).
(List<double>, List<Span>)? storedDetect(String outDir) {
  final stillFile = File(p.join(outDir, 'still.jsonl'));
  final scenes = readJson(File(p.join(outDir, 'scenes.json')));
  if (scenes is! List || !stillFile.existsSync()) return null;
  final still = readJsonl(
    stillFile,
    accept: (m) {
      _span(m);
      return true;
    },
  );
  if (!still.clean) return null;
  try {
    return (
      [for (final n in scenes) (n as num).toDouble()],
      [for (final r in still.rows) _span(r)],
    );
  } on Object {
    return null;
  }
}
