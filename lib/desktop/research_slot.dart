/// The research game slot on PlayStudy's side: the approval file it owns,
/// the enforcer op that registers it, and what the enforcer blocks.
///
/// Paths (env seams): `GAME_RESEARCH_APPROVAL` (the file,
/// `~/.config/game-research/research_game.json`),
/// `GAME_RESEARCH_ENFORCER_SOCK` (`/run/steam-backlog-enforcer/ctl.sock`;
/// none in test mode unless set) and `GAME_RESEARCH_ENFORCER_DIR` (its
/// readable config, `~/.config/steam_backlog_enforcer`).
library;

import 'dart:io';

import 'package:game_research/core/research_game.dart';
import 'package:game_research/core/safe_json.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/enforcer_ctl.dart';
import 'package:game_research/desktop/recording_flag.dart';
import 'package:path/path.dart' as p;

/// How an add ended.
enum ResearchAdd {
  /// Approved and registered.
  added,

  /// Another game holds the slot.
  taken,

  /// The enforcer refused or did not answer; nothing changed.
  refused,
}

/// The slot.
class ResearchSlot {
  /// Creates the slot over [config].
  new(this.config)
    : file = File(
        _env(config, 'APPROVAL') ??
            p.join(
              config.home,
              '.config',
              'game-research',
              'research_game.json',
            ),
      ),
      enforcerDir =
          _env(config, 'ENFORCER_DIR') ??
          p.join(config.home, '.config', 'steam_backlog_enforcer'),
      ctl = EnforcerCtl(
        _env(config, 'ENFORCER_SOCK') ??
            (config.testMode ? '' : '/run/steam-backlog-enforcer/ctl.sock'),
      );

  static String? _env(Config c, String key) {
    final v = c.env['GAME_RESEARCH_$key'];
    return v == null || v.isEmpty ? null : v;
  }

  /// Settings.
  final Config config;

  /// The approval file.
  final File file;

  /// The enforcer's config folder.
  final String enforcerDir;

  /// The control socket.
  final EnforcerCtl ctl;

  /// Up from "Steam asked to start the game" until recording.
  RecordingFlag get launchFlag =>
      RecordingFlag(config.dataDir, name: 'research_launch.pid');

  /// The approval, or null.
  ResearchApproval? current() => file.existsSync()
      ? ResearchApproval.parse(file.readAsStringSync())
      : null;

  /// The research game's app id, or null.
  int? get appid => current()?.appid;

  /// Owned games (app id -> name), from the enforcer's cache.
  Map<int, String> owned() => ownedGames(_read('owned_app_ids_cache.json'));

  /// App ids the enforcer allows anyway.
  Set<int> allowed() => enforcerAllowed(
    state: _read('state.json'),
    exceptions: _read('approved_exceptions.json'),
    zeroAchievements: _read('no_achievements_cache.json'),
  );

  String _read(String name) {
    final f = File(p.join(enforcerDir, name));
    try {
      return f.readAsStringSync();
    } on FileSystemException {
      return '';
    }
  }

  /// Approves [appid]; refused while another game holds the slot. Re-adding
  /// the same game re-registers it.
  Future<ResearchAdd> add(int appid, {double now = 0}) async {
    final held = appid == this.appid ? null : current();
    if (held != null) return ResearchAdd.taken;
    final flags = [
      p.join(config.dataDir, 'recording.pid'),
      launchFlag.file.path,
    ];
    writeAtomic(
      file,
      ResearchApproval(appid, addedAt: now, flags: flags).toJsonText(),
    );
    try {
      await ctl.call('research_game', {'app_id': appid});
    } on EnforcerError {
      file.deleteSync();
      return ResearchAdd.refused;
    }
    return ResearchAdd.added;
  }

  /// Removes the research game (revoked at once: the file is gone); null
  /// when there was none. Deletes nothing else.
  Future<int?> remove() async {
    final id = appid;
    if (file.existsSync()) file.deleteSync();
    if (id == null) return null;
    try {
      await ctl.call('research_game_revoke');
    } on EnforcerError {
      // The file is gone, so the enforcer already ignores its record.
    }
    return id;
  }
}
