/// Steam's on-disk library: `appmanifest_<id>.acf` and `libraryfolders.vdf`.
///
/// Both are Valve KeyValues text. Only top-level `"key" "value"` pairs of the
/// AppState block are read; nested blocks (UserConfig, InstalledDepots) are
/// skipped so their keys cannot shadow the game's own name.
library;

/// One installed game.
class SteamGame {
  /// Creates a game.
  const new({required this.appid, required this.name, this.installed = true});

  /// Steam app id.
  final int appid;

  /// Store name. Never drawn in the UI (text-free); it is the tile's
  /// accessibility label and the folder slug.
  final String name;

  /// Whether Steam reports it fully installed.
  final bool installed;

  /// The `/api/games` object.
  Map<String, Object?> toJson() => {'appid': appid, 'name': name};
}

final _pair = RegExp(r'"([^"]*)"\s*"([^"]*)"');
final _token = RegExp(r'"(?:[^"\\]|\\.)*"|[{}]');

/// Top-level key/value pairs of the first block in a KeyValues [text].
Map<String, String> _topLevel(String text) {
  final out = <String, String>{};
  var depth = 0;
  String? pendingKey;
  for (final m in _token.allMatches(text)) {
    final tok = m[0]!;
    if (tok == '{') {
      depth++;
      pendingKey = null;
    } else if (tok == '}') {
      depth--;
    } else if (depth == 1) {
      final value = tok.substring(1, tok.length - 1);
      if (pendingKey == null) {
        pendingKey = value;
      } else {
        out.putIfAbsent(pendingKey.toLowerCase(), () => value);
        pendingKey = null;
      }
    }
  }
  return out;
}

// StateFlags bit 4 = fully installed; 1026 etc. mean updating/downloading.
const _installedFlag = 4;
const int _busyMask = 2 | 512 | 1024;

/// The game in one manifest, or null without a numeric appid and a name.
SteamGame? parseAcf(String text) {
  final kv = _topLevel(text);
  final appid = int.tryParse(kv['appid'] ?? '');
  final name = kv['name'];
  if (appid == null || name == null || name.isEmpty) return null;
  final flags = int.tryParse(kv['stateflags'] ?? '');
  final installed =
      flags == null || (flags & _installedFlag != 0 && flags & _busyMask == 0);
  return SteamGame(appid: appid, name: name, installed: installed);
}

/// Proton, runtimes and redistributables: in steamapps, never a game.
bool isSteamTool(String name) =>
    RegExp(r'^(Proton\b|Steam Linux Runtime|Steamworks Common)').hasMatch(name);

/// Capsule image paths under `appcache/librarycache`, best first. Newer
/// clients keep a folder per app (sometimes with a hashed subfolder, found
/// by the scanner); older ones flat `<id>_library_600x900.jpg` files.
List<String> capsuleCandidates(int appid) => [
  '$appid/library_600x900.jpg',
  '$appid/library_capsule.jpg',
  '${appid}_library_600x900.jpg',
  '$appid/header.jpg',
  '${appid}_header.jpg',
];

/// Every library root listed in `libraryfolders.vdf`.
List<String> libraryPaths(String vdf) => [
  for (final m in _pair.allMatches(vdf))
    if (m[1]!.toLowerCase() == 'path') m[2]!.replaceAll(r'\\', r'\'),
];

/// What `steam` is given to launch [appid].
String runGameUri(int appid) => 'steam://rungameid/$appid';
