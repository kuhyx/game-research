/// Target projects: repos whose questions template a draft fills.
///
/// A target is any folder under [Config.srcRoot] holding
/// `docs/research/DOCS-research-questions.md`, plus the default target
/// (cleanup-plate) even before its template exists. The pick is kept in
/// `<dataDir>/settings.json`.
library;

import 'dart:io';

import 'package:game_research/core/synthesis.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/settings_file.dart';
import 'package:path/path.dart' as p;

/// The target list and the current pick.
class Targets {
  /// Creates the list.
  const new(this.config);

  /// Settings.
  final Config config;

  /// `<dataDir>/settings.json`, shared with the last-game key.
  SettingsFile get settings =>
      SettingsFile(p.join(config.dataDir, 'settings.json'));

  /// Candidate target folders, default first, then by name.
  List<String> list() {
    final found = <String>{config.defaultTarget};
    final root = Directory(config.srcRoot);
    if (root.existsSync()) {
      final dirs = root.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final d in dirs) {
        if (File(templatePaths(d.path).en).existsSync()) found.add(d.path);
      }
    }
    return found.toList();
  }

  /// The picked target, or the default when none (or a vanished one) is set.
  String current() {
    final t = settings.read()['target'];
    return t is String && list().contains(t) ? t : config.defaultTarget;
  }

  /// Picks [target]; false when it is not in [list].
  bool pick(String target) {
    if (!list().contains(target)) return false;
    settings.merge({'target': target});
    return true;
  }

  /// `/api/targets`: each target's path and folder name, the current one.
  Map<String, Object?> toJson() => {
    'current': current(),
    'targets': [
      for (final t in list()) {'path': t, 'name': p.basename(t)},
    ],
  };
}
