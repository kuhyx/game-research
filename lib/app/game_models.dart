/// A library game, its enforcer lock and its "research finished" job, from
/// `/api/games`.
library;

import 'package:game_research/app/job_models.dart';
import 'package:game_research/core/research_game.dart';

export 'package:game_research/core/research_game.dart' show TileLock;

TileLock _lock(Object? v) => TileLock.values.asNameMap()[v] ?? TileLock.open;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// One library game.
class Game {
  /// Creates a game.
  const new({
    required this.appid,
    required this.name,
    this.capsule = false,
    this.installed = true,
    this.lock = TileLock.open,
    this.updating = false,
    this.progress = 1,
    this.slug = '',
    this.finish,
  });

  /// Parses one `/api/games` entry.
  factory fromJson(Map<String, Object?> j) => Game(
    appid: _int(j['appid']),
    name: '${j['name'] ?? ''}',
    capsule: j['capsule'] == true,
    installed: j['state'] != 'absent',
    lock: _lock(j['lock']),
    updating: j['state'] == 'updating',
    progress: (j['progress'] as num?)?.toDouble() ?? 1,
    slug: '${j['slug'] ?? ''}',
    finish: j['finish'] is Map ? Finish.fromJson(j['finish']! as Map) : null,
  );

  /// Steam app id.
  final int appid;

  /// Name: accessibility label only, never drawn.
  final String name;

  /// Whether a capsule image exists.
  final bool capsule;

  /// Has a Steam manifest (installed or downloading); false: owned only.
  final bool installed;

  /// What the enforcer does with it.
  final TileLock lock;

  /// The research game, not on disk yet or still downloading.
  bool get installing => lock == TileLock.research && (!installed || updating);

  /// Steam stopped mid-download; starting it lets Steam finish first.
  final bool updating;

  /// Downloaded share, 0..1.
  final double progress;

  /// File-name slug of the game (the finish job's key).
  final String slug;

  /// The "research finished" job of this game, once it ran.
  final Finish? finish;

  /// This game with its finish state replaced by [f].
  Game withFinish(Finish? f) => Game(
    appid: appid,
    name: name,
    capsule: capsule,
    installed: installed,
    lock: lock,
    updating: updating,
    progress: progress,
    slug: slug,
    finish: f,
  );
}

/// The per-game "research finished" job: progress plus the two documents.
class Finish {
  /// Creates the info.
  const new(this.job, {this.report, this.merged});

  /// Parses the `finish` object of `/api/games`.
  factory fromJson(Map<Object?, Object?> j) => Finish(
    JobStatus.fromJson(j),
    report: j['report'] as String?,
    merged: j['merged'] as String?,
  );

  /// Progress, tokens and state.
  final JobStatus job;

  /// Path of the human-readable report, once written.
  final String? report;

  /// Path of the merged answers document.
  final String? merged;

  /// Shortcut for `job.state`.
  String get state => job.state;
}
