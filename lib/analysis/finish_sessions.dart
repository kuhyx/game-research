/// Where a game's finish state lives and which sessions it merges.
library;

import 'dart:io';

import 'package:game_research/core/safe_json.dart';
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

/// The analysed sessions of [slug] under [dataDir], oldest first. A v1
/// session's `stage3.json` has the flat `draft_en` instead of `draft`; v1
/// sessions of one game share that file, so a path counts once, for the
/// newest session that names it.
List<FinishSession> analysedSessions(String dataDir, String slug) {
  final root = Directory(dataDir);
  if (!root.existsSync()) return const [];
  final byDraft = <String, FinishSession>{};
  final dirs = root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final d in dirs) {
    final meta = File(p.join(d.path, 'session.json'));
    final s3 = File(p.join(d.path, 'analysis', 'stage3.json'));
    if (!meta.existsSync() || !s3.existsSync()) continue;
    final m = readJsonObject(meta);
    final state = readJsonObject(s3);
    if (m == null || state == null) continue;
    final draft = state['draft'] ?? state['draft_en'];
    if (m['slug'] != slug || draft is! String) continue;
    if (!File(draft).existsSync()) continue;
    byDraft[draft] = FinishSession(
      d.path,
      '${m['game']}',
      '${m['target']}',
      draft,
    );
  }
  return byDraft.values.toList()..sort((a, b) => a.dir.compareTo(b.dir));
}
