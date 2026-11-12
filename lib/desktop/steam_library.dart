/// Installed Steam games and their capsule images, read from disk.
///
/// Reads Steam's own librarycache; only [SteamLibrary.art] may reach the CDN
/// (through [SteamArt]) for a game Steam never cached. A game with no image
/// at all gets a procedural tile in the GUI.
library;

import 'dart:io';

import 'package:game_research/core/steam.dart';
import 'package:game_research/desktop/steam_art.dart';
import 'package:path/path.dart' as p;

/// The library under one Steam root.
class SteamLibrary {
  /// Reads [steamRoot] (`~/.local/share/Steam`); [art] downloads the art
  /// Steam never cached (null: disk only).
  const new(this.steamRoot, {SteamArt? art}) : downloads = art;

  /// Steam's root folder.
  final String steamRoot;

  /// The CDN download cache.
  final SteamArt? downloads;

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

  /// Games, installed or mid-download (no tools), by name, one per id.
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
        if (game == null || isSteamTool(game.name)) continue;
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

  /// Portrait art Steam cached: flat `<id>_library_600x900.jpg`, or inside
  /// `<id>/` (also one hashed folder deeper, the newer layout).
  File? localPortrait(int appid) =>
      _find(appid, const ['library_600x900', 'library_capsule']);

  /// Landscape header, then the icon-sized `<id>/<hash>.jpg`: poor tiles,
  /// used only when nothing better exists.
  File? localFallback(int appid) {
    final header = _find(appid, const ['library_header', 'header']);
    if (header != null) return header;
    final appDir = Directory(p.join(_cache, '$appid'));
    if (!appDir.existsSync()) return null;
    for (final e in appDir.listSync().whereType<File>()) {
      if (e.path.endsWith('.jpg')) return e;
    }
    return null;
  }

  /// The best image on disk (portrait, else fallback), or null. Never
  /// touches the network.
  File? capsule(int appid) => localPortrait(appid) ?? localFallback(appid);

  /// The image to serve: a local portrait, else the download cache (fetching
  /// when allowed), else the local fallback.
  Future<File?> art(int appid) async {
    final local = localPortrait(appid);
    if (local != null) return local;
    final loaded = await downloads?.get(appid);
    return loaded ?? localFallback(appid);
  }

  /// Whether [art] may yield an image (the `capsule` flag of `/api/games`):
  /// something on disk, a cached download, or a download not ruled out.
  bool capsuleExpected(int appid) {
    if (capsule(appid) != null) return true;
    final a = downloads;
    return a != null && (a.cached(appid) != null || !a.missActive(appid));
  }

  String get _cache => p.join(steamRoot, 'appcache', 'librarycache');

  File? _find(int appid, List<String> prefixes) {
    for (final prefix in prefixes) {
      final flat = File(p.join(_cache, '${appid}_$prefix.jpg'));
      if (flat.existsSync()) return flat;
    }
    final appDir = Directory(p.join(_cache, '$appid'));
    if (!appDir.existsSync()) return null;
    final files = appDir.listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final prefix in prefixes) {
      for (final f in files) {
        final name = p.basename(f.path);
        if (name.startsWith(prefix) && name.endsWith('.jpg')) return f;
      }
    }
    return null;
  }
}
