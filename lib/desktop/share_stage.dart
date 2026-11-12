/// Stages the stills of a note part for the clipboard.
///
/// A part may span several sessions, and each session names its stills
/// `m_NN_<tag>.jpg`, so two files can share a basename. In Discord the order
/// of the pasted images is the only thing that pairs an image with its note
/// line, so the files are copied into a fresh folder under
/// `<data>/share/<slug>-<n>/` as `01_<tag>.jpg`, `02_<tag>.jpg`, ... in the
/// part's line order. Dart cannot hardlink without a process, and a handful
/// of JPEGs is cheap, so they are copied.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// One still to stage: its `source` file and the `tag` of its marker.
typedef StillSource = ({File source, String tag});

/// Copies [stills] (line order) into a fresh `<dataDir>/share/<slug>-<n>/`
/// and returns the staged paths in the same order. An earlier staging of the
/// same part is replaced.
List<String> stageStills(
  String dataDir,
  String slug,
  int n,
  List<StillSource> stills,
) {
  final dir = Directory(p.join(dataDir, 'share', '$slug-$n'));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final width = '${stills.length}'.length < 2 ? 2 : '${stills.length}'.length;
  return [
    for (var i = 0; i < stills.length; i++)
      stills[i].source
          .copySync(
            p.join(
              dir.path,
              '${'${i + 1}'.padLeft(width, '0')}_${stills[i].tag}.jpg',
            ),
          )
          .path,
  ];
}
