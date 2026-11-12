/// One full-resolution JPEG per marker, beside the marker's clip
/// (`analysis/clips/m_NN_<tag>.jpg`), for pasting into a Discord DM next to
/// kuhy's note. Stage 1 cuts them with the clips; the wrapper cuts the
/// missing ones of older sessions on demand (`notes_api.dart`).
library;

import 'dart:io';

import 'package:game_research/core/markers.dart';
import 'package:game_research/core/share_contract.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// The folder holding a session's stills and clips.
String clipsDir(String sessionDir) => p.join(sessionDir, 'analysis', 'clips');

/// The still file of marker [i] (1-based) of a session.
File stillFile(String sessionDir, int i, MarkerTag tag) =>
    File(p.join(clipsDir(sessionDir), stillName(i, tag)));

/// Whether every marker already has its still.
bool stillsComplete(String sessionDir, List<Marker> markers) => [
  for (var i = 0; i < markers.length; i++)
    stillFile(sessionDir, i + 1, markers[i].tag),
].every((f) => f.existsSync());

/// Extracts the missing stills of [markers] (in `parseMarkers` order) from
/// `recording.mkv` of [sessionDir]; existing ones are kept, so a rerun
/// resumes. [gate] is awaited before each ffmpeg call. A still ffmpeg cannot
/// cut (a marker past the end of a cut-short recording) is left out: the
/// analysis does not depend on it. Returns the names that exist afterwards.
Future<List<String>> extractStills(
  Sys sys,
  String sessionDir,
  List<Marker> markers, {
  Future<void> Function()? gate,
}) async {
  Directory(clipsDir(sessionDir)).createSync(recursive: true);
  final video = p.join(sessionDir, 'recording.mkv');
  final names = <String>[];
  for (var i = 0; i < markers.length; i++) {
    final out = stillFile(sessionDir, i + 1, markers[i].tag);
    if (!out.existsSync()) {
      await gate?.call();
      // Written beside the target and renamed: a reader never sees half a
      // JPEG, and a concurrent extraction of the same still is harmless.
      final part = '${out.path}.part.jpg';
      final r = await sys.run(
        'ffmpeg',
        stillArgv(video, markers[i].offsetS, part),
      );
      final tmp = File(part);
      if (r.exitCode == 0 && tmp.existsSync()) tmp.renameSync(out.path);
      if (tmp.existsSync()) tmp.deleteSync();
    }
    if (out.existsSync()) names.add(p.basename(out.path));
  }
  return names;
}
