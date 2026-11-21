/// The research game: one game the steam-backlog-enforcer blocks that kuhy
/// may install and play here, always recorded (kuhy, 2026-11-21).
///
/// PlayStudy owns the approval file (`~/.config/game-research/
/// research_game.json`, [ResearchApproval]); the enforcer honours it once
/// its `research_game` control-socket op registered the same app id, and
/// spares the game's process only while one of [ResearchApproval.flags]
/// names this live wrapper. One game at a time: a second one is refused
/// until the first is removed.
library;

import 'dart:convert';

/// The approval file's content.
class ResearchApproval {
  /// Creates an approval of [appid].
  const new(this.appid, {required this.addedAt, this.flags = const []});

  /// Parses the file; null when it is not a valid approval (fail closed).
  static ResearchApproval? parse(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;
    final id = j['app_id'];
    if (id is! int || id <= 0) return null;
    final flags = j['flags'];
    return ResearchApproval(
      id,
      addedAt: (j['added_at'] as num?)?.toDouble() ?? 0,
      flags: flags is List ? [for (final f in flags) '$f'] : const [],
    );
  }

  /// Steam app id.
  final int appid;

  /// When it was added, unix seconds.
  final double addedAt;

  /// Absolute paths of the session flags (pid files) the enforcer checks.
  final List<String> flags;

  /// The file's text.
  String toJsonText() => '${jsonEncode(toJson())}\n';

  /// The file's JSON.
  Map<String, Object?> toJson() => {
    'app_id': appid,
    'added_at': addedAt,
    'flags': flags,
  };
}

/// What a picker tile shows about the enforcer.
enum TileLock {
  /// Playable as usual.
  open,

  /// Blocked by the enforcer; tapping offers to add it as research game.
  blocked,

  /// The research game.
  research,

  /// Blocked, and the research slot is taken by another game.
  taken,
}

/// The lock of [appid]: [installed] games and [allowed] ones are open.
TileLock tileLock({
  required int appid,
  required bool installed,
  required Set<int> allowed,
  required int? research,
}) {
  if (appid == research) return TileLock.research;
  if (installed || allowed.contains(appid)) return TileLock.open;
  return research == null ? TileLock.blocked : TileLock.taken;
}

Object? _json(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// App id -> name of every owned game in the enforcer's
/// `owned_app_ids_cache.json`; empty when unreadable.
Map<int, String> ownedGames(String text) {
  final j = _json(text);
  final games = j is Map ? j['games'] : null;
  if (games is! List) return const {};
  return {
    for (final g in games)
      if (g is Map && g['app_id'] is int)
        g['app_id'] as int: '${g['name'] ?? ''}',
  };
}

/// App ids the enforcer lets kuhy play: the assignment, the manual picks,
/// the approved exceptions and the games with no achievements.
Set<int> enforcerAllowed({
  required String state,
  required String exceptions,
  required String zeroAchievements,
}) {
  final ids = <int>{};
  final s = _json(state);
  if (s is Map) {
    if (s['current_app_id'] case final int id) ids.add(id);
    if (s['manual_picks'] case final List<Object?> picks) {
      for (final p in picks) {
        if (p is Map && p['app_id'] is int) ids.add(p['app_id'] as int);
      }
    }
  }
  if (_json(exceptions) case final List<Object?> list) {
    for (final e in list) {
      if (e is Map && e['app_id'] is int) ids.add(e['app_id'] as int);
    }
  }
  if (_json(zeroAchievements) case {
    'checked': final Map<String, Object?> checked,
  }) {
    for (final k in checked.keys) {
      if (int.tryParse(k) case final int id) ids.add(id);
    }
  }
  return ids;
}
