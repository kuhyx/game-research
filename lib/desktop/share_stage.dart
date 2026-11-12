/// Stages the captioned stills of a copy for the clipboard.
///
/// A part may span several sessions, and each session names its stills
/// `m_NN_<tag>.jpg`, so two files can share a basename. In Discord the order
/// of the pasted images is the only thing that pairs an image with its note
/// line, so the images are written into a fresh folder under
/// `<data>/share/<name>/` as `01_<tag>.jpg`, `02_<tag>.jpg`, ... in the
/// part's line order. Each is the still with a dark band added below it that
/// carries the note (`helpers/caption_still.py`, run through [Sys]): in
/// Chromium a paste with files drops text, so the note must be in the image.
/// The originals in `analysis/clips` are never touched.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// The captioner failed (nothing is copied then).
class CaptionFailed implements Exception {
  /// Creates the failure.
  const new(this.message);

  /// Why.
  final String message;
}

/// One still to stage: its `source` file and what the band says.
typedef StillSource = ({
  File source,
  String tag,
  String time,
  String note,
  String right,
});

/// Renders [stills] (line order) into a fresh `<dataDir>/share/<name>/` and
/// returns the staged paths in the same order. An earlier staging of the
/// same name is replaced. Throws [CaptionFailed].
Future<List<String>> stageStills(
  Sys sys,
  Config config,
  String name,
  List<StillSource> stills,
) async {
  final dir = Directory(p.join(config.dataDir, 'share', name));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final width = '${stills.length}'.length < 2 ? 2 : '${stills.length}'.length;
  final jobs = [
    for (var i = 0; i < stills.length; i++)
      {
        'src': stills[i].source.path,
        'out': p.join(
          dir.path,
          '${'${i + 1}'.padLeft(width, '0')}_${stills[i].tag}.jpg',
        ),
        'tag': stills[i].tag,
        'time': stills[i].time,
        'note': stills[i].note,
        'right': stills[i].right,
      },
  ];
  final spec = File(p.join(config.dataDir, 'share', '$name.jobs.json'))
    ..writeAsStringSync(jsonEncode(jobs));
  try {
    final r = await sys.run(config.captionCmd.first, [
      ...config.captionCmd.skip(1),
      spec.path,
    ]);
    if (r.exitCode != 0) {
      throw CaptionFailed('captioner exited ${r.exitCode}: ${r.stderr}'.trim());
    }
  } on ProcessException catch (e) {
    throw CaptionFailed('captioner did not start: ${e.message}');
  } finally {
    spec.deleteSync();
  }
  final out = [for (final j in jobs) j['out']!];
  if (!out.every((f) => File(f).existsSync())) {
    throw const CaptionFailed('captioner wrote no image');
  }
  return out;
}
