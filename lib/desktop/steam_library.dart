/// Installed Steam games and their capsule images, read from disk.
///
/// Read-only: nothing here talks to Steam or its CDN. A game with no cached
/// capsule gets a procedural tile in the GUI instead.
library;

import 'dart:io';

import 'package:game_research/core/steam.dart';
import 'package:path/path.dart' as p;

/// The library under one Steam root.
class SteamLibrary {
  /// Reads [steamRoot] (`~/.local/share/Steam`).
  const new(this.steamRoot);

  /// Steam's root folder.
  final String steamRoot;

  /// Every `steamapps/` folder: the root's, plus each library folder.
  List<String> _steamappsDirs() {
    final dirs = <String>{p.join(steamRoot, 'steamapps')};
    final vdf = File(p.join(steamRoot, 'steamapps', 'libraryfolders.vdf'));
    if (vdf.existsSync()) {
      for (final root in libraryPaths(vdf.readAsStringSync())) {
        dirs.add(p.join(root, 'steamapps'));
      }
    }
    return dirs.toList();
  }

  /// Installed games (no tools, nothing mid-download), by name, one per id.
  List<SteamGame> games() {
    final byId = <int, SteamGame>{};
    for (final dir in _steamappsDirs()) {
      final folder = Directory(dir);
      if (!folder.existsSync()) continue;
      for (final f in folder.listSync().whereType<File>()) {
        final name = p.basename(f.path);
        if (!name.startsWith('appmanifest_') || !name.endsWith('.acf')) {
          continue;
        }
        final game = parseAcf(f.readAsStringSync());
        if (game == null || !game.installed || isSteamTool(game.name)) continue;
        byId.putIfAbsent(game.appid, () => game);
      }
    }
    return byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// The game with [appid], or null.
  SteamGame? find(int appid) {
    for (final g in games()) {
      if (g.appid == appid) return g;
    }
    return null;
  }

  /// The best cached capsule image of [appid], or null.
  File? capsule(int appid) {
    final cache = p.join(steamRoot, 'appcache', 'librarycache');
    for (final rel in capsuleCandidates(appid)) {
      final f = File(p.join(cache, rel));
      if (f.existsSync()) return f;
    }
    // Newer clients may nest the art one hashed folder deeper.
    final appDir = Directory(p.join(cache, '$appid'));
    if (!appDir.existsSync()) return null;
    for (final e in appDir.listSync(recursive: true).whereType<File>()) {
      if (p.basename(e.path).startsWith('library_600x900')) return e;
    }
    return null;
  }
}
