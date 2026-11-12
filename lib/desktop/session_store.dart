/// Past sessions on disk, and starting their analysis job.
///
/// A session folder holds `session.json` (written by the controller),
/// `markers.jsonl`, `recording.mkv` and `analysis/` (written by the job).
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/markers.dart';
import 'package:game_research/core/safe_json.dart' show writeAtomic;
import 'package:game_research/core/status.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/status_view.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// Reads and writes session folders under [Config.dataDir].
class SessionStore {
  /// Creates the store.
  const new(this.config);

  /// Settings.
  final Config config;

  /// The folder of session [id]; null for an id that is not a plain name.
  Directory? dir(String id) {
    if (id.isEmpty || id != p.basename(id) || id.startsWith('.')) return null;
    final d = Directory(p.join(config.dataDir, id));
    return d.existsSync() ? d : null;
  }

  /// `session.json` of [dir].
  Map<String, Object?> meta(Directory dir) =>
      readJson(File(p.join(dir.path, 'session.json')));

  /// Writes `session.json` of [dir].
  void writeMeta(Directory dir, Map<String, Object?> meta) => writeAtomic(
    File(p.join(dir.path, 'session.json')),
    const JsonEncoder.withIndent(' ').convert(meta),
  );

  /// The analysis status of [dir].
  AnalysisStatus status(Directory dir) => AnalysisStatus.fromJson(
    readJson(File(p.join(dir.path, 'analysis', 'status.json'))),
  );

  /// One `/api/sessions` entry.
  Map<String, Object?> summary(Directory dir) {
    final meta = this.meta(dir);
    final markersFile = File(p.join(dir.path, 'markers.jsonl'));
    var counts = countByTag(const []);
    if (markersFile.existsSync()) {
      counts = countByTag(parseMarkers(markersFile.readAsStringSync()));
    }
    final stage3 = readJson(File(p.join(dir.path, 'analysis', 'stage3.json')));
    // `draft` (one per session); old sessions wrote `draft_en`.
    final draft = (stage3['draft'] ?? stage3['draft_en']) as String?;
    return {
      'id': p.basename(dir.path),
      'appid': meta['appid'],
      'game': meta['game'],
      'started_unix': meta['started_unix'],
      'duration_s': meta['duration_s'],
      'ended_by': meta['ended_by'],
      'recording': meta['state'] == 'recording',
      'markers': {for (final e in counts.entries) e.key.name: e.value},
      'analysis': statusView(
        readJson(File(p.join(dir.path, 'analysis', 'status.json'))),
      ),
      'fps': meta['fps'],
      'draft': draft != null && File(draft).existsSync() ? draft : null,
    };
  }

  /// Every session, newest first.
  List<Map<String, Object?>> list() {
    final root = Directory(config.dataDir);
    if (!root.existsSync()) return const [];
    final dirs =
        root
            .listSync()
            .whereType<Directory>()
            .where((d) => File(p.join(d.path, 'session.json')).existsSync())
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    return [for (final d in dirs) summary(d)];
  }
}

/// Starts the analysis job of a session folder.
class AnalysisLauncher {
  /// Creates the launcher.
  const new(this.config, this.sys);

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  /// The analyzer binary, built beside the wrapper's bundle
  /// (`dart build cli` builds one entry point per output folder).
  String get analyzer => p.join(
    config.repo,
    'build',
    'analyze',
    'bundle',
    'bin',
    'game_research_analyze',
  );

  /// Never compete with a game: idle CPU and IO class, lowest priority, and
  /// off the 7900X3D V-cache CCD (CPUs 0-5 and 12-17). Mirrors
  /// e2e/bgshim/systemd-run. CPUAffinity, not AllowedCPUs: the cpuset
  /// controller is not delegated to the user manager.
  static const backgroundProps = [
    'CPUAffinity=6-11 18-23',
    'Nice=19',
    'CPUSchedulingPolicy=idle',
    'IOSchedulingClass=idle',
  ];

  /// Starts the job for [dir]. `systemd`: a `systemd-run --user --collect`
  /// unit that outlives the wrapper; `inline`: a detached child (tests);
  /// `off`: nothing (off-screen agent runs must not call models or write
  /// drafts into the target repo). Returns false when it did not start.
  Future<bool> launch(Directory dir) => _start('analyze', [dir.path]);

  /// Starts the per-game "research finished" job for [slug] (merges every
  /// session draft into one document and a report).
  Future<bool> launchFinish(String slug) =>
      _start('finish', ['--finish', slug]);

  Future<bool> _start(String kind, List<String> args) async {
    if (config.analyzeMode == 'off') return false;
    if (config.analyzeMode == 'inline') {
      try {
        await sys.start(analyzer, args, mode: ProcessStartMode.detached);
        return true;
      } on ProcessException {
        return false;
      }
    }
    final stamp = (sys.nowUnix() * 1000).round();
    final env = {
      ...config.env,
      'HOME': config.home,
      // The user manager's PATH lacks ~/.local/bin (dart, claude).
      'PATH': '${config.home}/.local/bin:/usr/local/bin:/usr/bin',
    };
    final r = await sys.run('systemd-run', [
      '--user',
      '--collect',
      '--quiet',
      '--unit',
      'game-research-$kind-$stamp',
      '-p',
      'WorkingDirectory=${config.repo}',
      for (final prop in backgroundProps) ...['-p', prop],
      for (final e in env.entries) '--setenv=${e.key}=${e.value}',
      analyzer,
      ...args,
    ]);
    return r.exitCode == 0;
  }
}
