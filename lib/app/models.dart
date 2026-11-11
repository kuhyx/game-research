/// What the page shows, parsed from the wrapper's JSON.
library;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// One installed game.
class Game {
  /// Creates a game.
  const new({required this.appid, required this.name, this.capsule = false});

  /// Parses one `/api/games` entry.
  factory fromJson(Map<String, Object?> j) => Game(
    appid: _int(j['appid']),
    name: '${j['name'] ?? ''}',
    capsule: j['capsule'] == true,
  );

  /// Steam app id.
  final int appid;

  /// Name: accessibility label only, never drawn.
  final String name;

  /// Whether a capsule image exists.
  final bool capsule;
}

/// Marker counts per tag name.
typedef Counts = Map<String, int>;

Counts _counts(Object? v) => {
  for (final e in ((v as Map?) ?? const {}).entries) '${e.key}': _int(e.value),
};

/// `/api/state`.
class AppState {
  /// Creates a state.
  const new({
    this.recording = false,
    this.error = '',
    this.target = '',
    this.appid,
    this.startedUnix,
    this.counts = const {},
  });

  /// Parses `/api/state`.
  factory fromJson(Map<String, Object?> j) {
    final s = j['session'] as Map<String, Object?>?;
    return AppState(
      recording: j['recording'] == true,
      error: '${j['error'] ?? ''}',
      target: '${j['target'] ?? ''}',
      appid: s == null ? null : _int(s['appid']),
      startedUnix: (s?['started_unix'] as num?)?.toDouble(),
      counts: _counts(s?['markers']),
    );
  }

  /// Whether a session records.
  final bool recording;

  /// Why the last start/stop failed.
  final String error;

  /// Target project path.
  final String target;

  /// The recording game.
  final int? appid;

  /// Session start, unix seconds.
  final double? startedUnix;

  /// Markers so far.
  final Counts counts;
}

/// `/api/targets`.
class TargetList {
  /// Creates the list.
  const new({this.current = '', this.paths = const []});

  /// Parses `/api/targets`.
  factory fromJson(Map<String, Object?> j) => TargetList(
    current: '${j['current'] ?? ''}',
    paths: [
      for (final t in (j['targets'] as List?) ?? const [])
        '${(t as Map)['path']}',
    ],
  );

  /// The picked target.
  final String current;

  /// Every target path.
  final List<String> paths;
}

/// One past session.
class SessionRow {
  /// Creates a row.
  const new({
    required this.id,
    this.appid = 0,
    this.game = '',
    this.startedUnix = 0,
    this.durationS = 0,
    this.recording = false,
    this.counts = const {},
    this.progress = 0,
    this.state = 'idle',
    this.draft,
  });

  /// Parses one `/api/sessions` entry.
  factory fromJson(Map<String, Object?> j) {
    final a = (j['analysis'] as Map<String, Object?>?) ?? const {};
    return SessionRow(
      id: '${j['id']}',
      appid: _int(j['appid']),
      game: '${j['game'] ?? ''}',
      startedUnix: (j['started_unix'] as num?)?.toDouble() ?? 0,
      durationS: (j['duration_s'] as num?)?.toDouble() ?? 0,
      recording: j['recording'] == true,
      counts: _counts(j['markers']),
      progress: (a['progress'] as num?)?.toDouble() ?? 0,
      state: '${a['state'] ?? 'idle'}',
      draft: j['draft'] as String?,
    );
  }

  /// Folder name.
  final String id;

  /// Game id (for its capsule).
  final int appid;

  /// Game name (label only).
  final String game;

  /// Start, unix seconds.
  final double startedUnix;

  /// Length, seconds.
  final double durationS;

  /// Still recording.
  final bool recording;

  /// Markers per tag.
  final Counts counts;

  /// Analysis progress 0..1.
  final double progress;

  /// idle | running | done | failed.
  final String state;

  /// Path of the English draft, when written.
  final String? draft;
}

/// `mm:ss`, or `h:mm:ss` from an hour on.
String clock(double seconds) {
  final s = seconds < 0 ? 0 : seconds.floor();
  String two(int v) => v.toString().padLeft(2, '0');
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return h > 0 ? '$h:${two(m)}:${two(s % 60)}' : '${two(m)}:${two(s % 60)}';
}
