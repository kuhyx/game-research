/// The session-scoped global hotkeys, as an sxhkd config.
///
/// sxhkd runs only while a session records (started and stopped by the
/// wrapper with its own generated config), so Mod+F1..F4 are free the rest
/// of the time. Each key posts to the wrapper on loopback; the wrapper
/// stamps the marker on arrival.
library;

/// One hotkey: its sxhkd chord and the wrapper path it posts to.
class Hotkey {
  /// Creates a hotkey.
  const new(this.chord, this.path);

  /// sxhkd chord, e.g. `super + F1`.
  final String chord;

  /// Wrapper path and query.
  final String path;
}

/// Mod+F1 good, Mod+F2 bad, Mod+F3 confusing, Mod+F4 note (asks for a line
/// through dmenu), Mod+Shift+F4 stop.
const kHotkeys = [
  Hotkey('super + F1', '/api/marker?tag=good&src=key'),
  Hotkey('super + F2', '/api/marker?tag=bad&src=key'),
  Hotkey('super + F3', '/api/marker?tag=confusing&src=key'),
  Hotkey('super + F4', '/api/marker?tag=note&src=key&ask=1'),
  Hotkey('super + shift + F4', '/api/stop?src=key'),
];

/// [chord] spelt the way key caps read: `super + shift + F4` ->
/// `Super+Shift+F4`.
String keyLegend(String chord) => chord
    .split(' + ')
    .map((k) => '${k[0].toUpperCase()}${k.substring(1)}')
    .join('+');

/// The key legend bound to a marker [action] (`good`, `bad`, `confusing`,
/// `note`) or `stop`, read from [kHotkeys] (the bindings sxhkd gets), or
/// null when nothing is bound.
String? shortcutFor(String action) {
  for (final k in kHotkeys) {
    final uri = Uri.parse(k.path);
    final name = uri.path == '/api/stop' ? 'stop' : uri.queryParameters['tag'];
    if (name == action) return keyLegend(k.chord);
  }
  return null;
}

/// The sxhkd config posting to the wrapper on [port] with [curl].
String sxhkdConfig({required int port, String curl = 'curl'}) {
  final out = StringBuffer('# game-research session hotkeys (generated)\n');
  for (final k in kHotkeys) {
    out
      ..write('${k.chord}\n')
      ..write("\t$curl -fsS -m 3 -X POST 'http://127.0.0.1:$port${k.path}'\n");
  }
  return out.toString();
}

/// Turns an i3 key spec (`$mod+Shift+F4`) into our chord form, or null.
String? _chordOf(String keys, String mod) {
  final parts = keys
      .replaceAll(r'$mod', mod)
      .split('+')
      .map((s) => s.trim().toLowerCase())
      .toList();
  final key = parts.removeLast();
  final mods = parts.map((m) => m == 'mod4' ? 'super' : m).toSet();
  if (!RegExp(r'^f[1-4]$').hasMatch(key)) return null;
  final ordered = [
    if (mods.contains('super')) 'super',
    if (mods.contains('shift')) 'shift',
  ];
  if (ordered.length != mods.length) return null;
  return [...ordered, key.toUpperCase()].join(' + ');
}

/// Our chords that an uncommented i3 `bindsym` already uses, in file order.
List<String> i3Collisions(String i3Config) {
  final mod =
      RegExp(
        r'^\s*set\s+\$mod\s+(\S+)',
        multiLine: true,
      ).firstMatch(i3Config)?[1] ??
      'Mod4';
  final ours = {for (final k in kHotkeys) k.chord};
  final hits = <String>[];
  final bind = RegExp(
    r'^\s*bind(sym|code)\s+(?:--\S+\s+)*(\S+)',
    multiLine: true,
  );
  for (final m in bind.allMatches(i3Config)) {
    var keys = m[2]!;
    if (m[1] == 'code') {
      // X keycodes of F1..F4 on a standard evdev keymap.
      keys = keys.replaceAllMapped(
        RegExp(r'\b(6[7-9]|70)$'),
        (k) => 'F${int.parse(k[1]!) - 66}',
      );
    }
    final chord = _chordOf(keys, mod);
    if (chord != null && ours.contains(chord) && !hits.contains(chord)) {
      hits.add(chord);
    }
  }
  return hits;
}
