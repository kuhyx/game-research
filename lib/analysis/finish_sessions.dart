/// Where a game's finish state lives and which sessions it merges.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/synthesis.dart';
import 'package:path/path.dart' as p;

/// The folder of one game's finish state.
String gameStateDir(String dataDir, String slug) =>
    p.join(dataDir, 'games', slug);

/// An analysed session of a game: its draft exists in the target.
class FinishSession {
  /// Creates the record.
  const new(this.dir, this.game, this.target, this.draft);

  /// Session folder.
  final String dir;

  /// Game name.
  final String game;

  /// Target repo.
  final String target;

  /// The session's draft file.
  final String draft;

  /// The session stamp.
  String get stamp => sessionStamp(p.basename(dir));
}

/// The analysed sessions of [slug] under [dataDir], oldest first.
List<FinishSession> analysedSessions(String dataDir, String slug) {
  final root = Directory(dataDir);
  if (!root.existsSync()) return const [];
  final out = <FinishSession>[];
  for (final d in root.listSync().whereType<Directory>()) {
    final meta = File(p.join(d.path, 'session.json'));
    final s3 = File(p.join(d.path, 'analysis', 'stage3.json'));
    if (!meta.existsSync() || !s3.existsSync()) continue;
    final m = jsonDecode(meta.readAsStringSync()) as Map<String, Object?>;
    final draft = (jsonDecode(s3.readAsStringSync()) as Map)['draft'];
    if (m['slug'] != slug || draft is! String) continue;
    if (!File(draft).existsSync()) continue;
    out.add(FinishSession(d.path, '${m['game']}', '${m['target']}', draft));
  }
  return out..sort((a, b) => a.dir.compareTo(b.dir));
}
