/// Recording retention: `recording.mkv` is deleted [kRecordingKeepDays] days
/// after the game's `finish.json` says done. Everything else of a session
/// (the .ts, frames, clips, analysis) stays. Only sessions that finish.json
/// merged and whose own analysis is done lose their recording.
library;

import 'dart:io';

import 'package:game_research/core/safe_json.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:game_research/desktop/config.dart';
import 'package:path/path.dart' as p;

/// Days a recording is kept after the game's research is finished.
const kRecordingKeepDays = 14;

/// Deletes the recordings due at [nowUnix]; returns the deleted paths.
List<String> applyRetention(Config config, double nowUnix) {
  final games = Directory(p.join(config.dataDir, 'games'));
  if (!games.existsSync()) return const [];
  final root = Directory(config.dataDir);
  final deleted = <String>[];
  for (final g in games.listSync().whereType<Directory>()) {
    final finish = readJsonObject(File(p.join(g.path, 'finish.json')));
    final at = (finish?['finished_unix'] as num?)?.toDouble();
    if (finish == null || finish['state'] != 'done' || at == null) continue;
    if (nowUnix - at < kRecordingKeepDays * 86400) continue;
    final merged = ((finish['sessions'] as List?) ?? const []).cast<String>();
    for (final d in root.listSync().whereType<Directory>()) {
      final meta = readJsonObject(File(p.join(d.path, 'session.json')));
      final status = readJsonObject(
        File(p.join(d.path, 'analysis', 'status.json')),
      );
      final video = File(p.join(d.path, 'recording.mkv'));
      if (meta == null || meta['slug'] != p.basename(g.path)) continue;
      if (!merged.contains(sessionStamp(p.basename(d.path)))) continue;
      if (status?['state'] != StageState.done.name) continue;
      if (!video.existsSync()) continue;
      video.deleteSync();
      deleted.add(video.path);
    }
  }
  return deleted;
}
