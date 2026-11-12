/// Fixtures for the analysis tests: a session folder, a target repo with
/// templates, scripted ffmpeg output and a scripted fake model.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/markers.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';

/// A caption a tier can answer with.
const kCaptionJson = '{"screen":"menu","action":"waiting","prompt":""}';

/// A well-formed synthesis answer.
const kAnswer =
    '$kEnMarker\n# English\nbody\n$kPlMarker\n# Polski\ntresc\n$kEndMarker\n';

/// An ffmpeg log with one scene cut at 15 s and one 3 s still stretch.
const kScenesLog = '''
[Parsed_showinfo_3 @ 0x55] n:   0 pts:  45000 pts_time:15.0 pos: 1
[freezedetect @ 0x56] lavfi.freezedetect.freeze_start: 3.5
[freezedetect @ 0x56] lavfi.freezedetect.freeze_end: 6.5
''';

/// Plays ffmpeg: the detect pass (`-f null -`) logs [log] on stderr, every
/// other call writes its output file (a `%03d` pattern becomes `001`).
ProcessResult? ffmpegFake(Call c, {String log = kScenesLog}) {
  if (c.exe != 'ffmpeg') return null;
  final out = c.args.last;
  if (out == '-') return ProcessResult(1, 0, '', log);
  File(out.replaceAll('%03d', '001'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('out');
  return null;
}

/// A session folder with a target repo that has the questions templates.
class Fixture {
  /// Builds it under a fresh temp dir; [duration] null leaves it out.
  new({double? duration = 40, bool templates = true}) {
    root = tempDir();
    target = Directory(p.join(root.path, 'src', 'cleanup-plate'))
      ..createSync(recursive: true);
    session = Directory(p.join(root.path, 'data', '20261112-090025-alpha'))
      ..createSync(recursive: true);
    if (templates) {
      final t = templatePaths(target.path);
      File(t.en)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('# Q\n');
      File(t.pl).writeAsStringSync('# P\n');
    }
    meta = {
      'game': 'Alpha',
      'slug': 'alpha',
      'target': target.path,
      'duration_s': ?duration,
    };
    File(p.join(session.path, 'session.json'))
        .writeAsStringSync(jsonEncode(meta));
    File(p.join(session.path, 'recording.mkv')).writeAsStringSync('video');
    File(p.join(session.path, 'markers.jsonl')).writeAsStringSync(
      '${const Marker(wallUnix: 1, offsetS: 12, tag: MarkerTag.good).toLine()}'
      '\n',
    );
  }

  /// Temp root.
  late final Directory root;

  /// The target repo.
  late final Directory target;

  /// The session folder.
  late final Directory session;

  /// `session.json`.
  late final Map<String, Object?> meta;

  /// A file below the session's `analysis/`.
  File out(String name) => File(p.join(session.path, 'analysis', name));

  /// Parsed `analysis/status.json`.
  Map<String, Object?> get status =>
      jsonDecode(out('status.json').readAsStringSync()) as Map<String, Object?>;
}
