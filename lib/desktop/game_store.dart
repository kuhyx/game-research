/// Per-game state of the "research finished" job, from
/// `<data>/games/<slug>/{finish,status}.json` (written by the analyzer).
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/safe_json.dart'
    show readJsonObject, writeAtomic;
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
    final raw = newestIsStatus ? {...f, ...s} : {...s, ...f};
    // A request no analyzer picked up yet reads as waiting (the hourglass).
    if (raw['state'] == 'queued') raw['state'] = 'waiting';
    return {
      ...statusView(raw),
      'report': f['report'],
      'merged': f['merged'],
      'sessions': f['sessions'],
    };
  }

  /// Whether kuhy ever asked to finish [slug] (any state of `finish.json`).
  bool requested(String slug) =>
      File(p.join(dir(slug), 'finish.json')).existsSync();

  /// Durably records the request to finish [slug] before anything is
  /// launched: `finish.json` gets state `queued`, so a busy machine, a dead
  /// launcher or a restart cannot lose it (`--resume-all` picks it up). A
  /// finished game keeps its report and state (the job merges again only for
  /// new sessions); a `failed` status is cleared so the retry is not lost.
  void request(String slug, int appid, double nowUnix) {
    Directory(dir(slug)).createSync(recursive: true);
    final file = File(p.join(dir(slug), 'finish.json'));
    final old = readJsonObject(file) ?? <String, Object?>{};
    writeAtomic(
      file,
      const JsonEncoder.withIndent(' ').convert({
        ...old,
        'state': old['state'] == 'done' ? 'done' : 'queued',
        'appid': appid,
        'requested_unix': nowUnix,
      }),
    );
    final status = File(p.join(dir(slug), 'status.json'));
    if (readJson(status)['state'] == 'failed') status.deleteSync();
  }
}
