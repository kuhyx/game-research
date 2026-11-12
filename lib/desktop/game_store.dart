/// Per-game state of the "research finished" job, from
/// `<data>/games/<slug>/{finish,status}.json` (written by the analyzer).
library;

import 'dart:io';

import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/status_view.dart';
import 'package:path/path.dart' as p;

/// Reads the per-game folders.
class GameStore {
  /// Creates the store.
  const new(this.config);

  /// Settings.
  final Config config;

  /// `<data>/games/<slug>`.
  String dir(String slug) => p.join(config.dataDir, 'games', slug);

  /// The finish job of [slug] as the page shows it, or null when it never
  /// ran. The newer of status.json and finish.json decides the state (a
  /// rerun's status is newer than the last finish); report and merged paths
  /// come from finish.json so the old report stays openable meanwhile.
  Map<String, Object?>? finish(String slug) {
    final status = File(p.join(dir(slug), 'status.json'));
    final done = File(p.join(dir(slug), 'finish.json'));
    final s = readJson(status);
    final f = readJson(done);
    if (s.isEmpty && f.isEmpty) return null;
    final newestIsStatus =
        f.isEmpty ||
        (s.isNotEmpty &&
            status.lastModifiedSync().isAfter(done.lastModifiedSync()));
    return {
      ...statusView(newestIsStatus ? {...f, ...s} : {...s, ...f}),
      'report': f['report'],
      'merged': f['merged'],
      'sessions': f['sessions'],
    };
  }
}
