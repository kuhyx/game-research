/// Reading and editing one app's `LaunchOptions` in Steam's
/// `localconfig.vdf`, leaving every other byte of the file as it was.
///
/// The file is Valve's text KeyValues: `"key" "value"` pairs and
/// `"key" { ... }` blocks, quotes escaped as `\"` and backslashes as `\\`.
/// The option lives at
/// `UserLocalConfigStore/Software/Valve/Steam/apps/<appid>/LaunchOptions`.
/// Keys compare case-insensitively (Steam itself does).
library;

class _Str {
  const new(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

class _Entry {
  new(this.key);
  final _Str key;
  _Str? value;
  _Block? block;
}

class _Block {
  new(this.open);
  final int open;
  int close = -1;
  final entries = <_Entry>[];

  _Entry? find(String key) {
    for (final e in entries) {
      if (e.key.text.toLowerCase() == key.toLowerCase()) return e;
    }
    return null;
  }
}

class _Parser {
  new(this.src);
  final String src;
  int pos = 0;

  void _skip() {
    while (pos < src.length) {
      final c = src[pos];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        pos++;
      } else if (src.startsWith('//', pos)) {
        while (pos < src.length && src[pos] != '\n') {
          pos++;
        }
      } else {
        return;
      }
    }
  }

  /// The next string token (quoted or bare), or null at `{`, `}` or the end.
  _Str? _string() {
    _skip();
    if (pos >= src.length || src[pos] == '{' || src[pos] == '}') return null;
    final start = pos;
    final out = StringBuffer();
    if (src[pos] == '"') {
      pos++;
      while (pos < src.length && src[pos] != '"') {
        if (src[pos] == r'\' && pos + 1 < src.length) {
          pos++;
          out.write(switch (src[pos]) {
            'n' => '\n',
            't' => '\t',
            final c => c,
          });
        } else {
          out.write(src[pos]);
        }
        pos++;
      }
      if (pos >= src.length) throw const FormatException('unterminated string');
      pos++;
    } else {
      while (pos < src.length && !' \t\r\n{}"'.contains(src[pos])) {
        out.write(src[pos++]);
      }
    }
    return _Str(start, pos, out.toString());
  }

  /// Entries up to the closing brace (or the end of the text at top level).
  _Block block({required bool top}) {
    final b = _Block(pos - 1);
    while (true) {
      final key = _string();
      if (key == null) {
        _skip();
        final atEnd = pos >= src.length;
        if (top ? !atEnd : atEnd || src[pos] != '}') {
          throw FormatException(top ? 'stray brace' : 'unterminated block');
        }
        b.close = pos;
        if (!top) pos++;
        return b;
      }
      final e = _Entry(key);
      _skip();
      if (pos < src.length && src[pos] == '{') {
        pos++;
        e.block = block(top: false);
      } else {
        e.value = _string() ?? (throw const FormatException('missing value'));
      }
      b.entries.add(e);
    }
  }
}

const _path = ['Software', 'Valve', 'Steam', 'apps'];

/// The `apps` block and the file's root, or null when the file lacks them.
_Block? _apps(_Block root) {
  var cur = root.find('UserLocalConfigStore')?.block;
  for (final key in _path) {
    cur = cur?.find(key)?.block;
  }
  return cur;
}

String _quote(String v) =>
    '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

/// The `LaunchOptions` of [appid] in [vdf]; null when it has none.
String? launchOption(String vdf, int appid) {
  final root = _Parser(vdf).block(top: true);
  final app = _apps(root)?.find('$appid')?.block;
  return app?.find('LaunchOptions')?.value?.text;
}

String _indentOf(String text, int at) {
  final lineStart = text.lastIndexOf('\n', at - 1) + 1;
  final before = text.substring(lineStart, at);
  return before.trim().isEmpty ? before : '';
}

/// [vdf] with [appid]'s `LaunchOptions` set to [value]; null when it
/// already is. Throws [FormatException] when the file is not a
/// `localconfig.vdf` (no `apps` block) so nothing is written blind.
String? setLaunchOption(String vdf, int appid, String value) {
  final apps = _apps(_Parser(vdf).block(top: true));
  if (apps == null) throw const FormatException('no apps block');
  final app = apps.find('$appid')?.block;
  final existing = app?.find('LaunchOptions')?.value;
  if (existing != null) {
    if (existing.text == value) return null;
    return vdf.replaceRange(existing.start, existing.end, _quote(value));
  }
  final target = app ?? apps;
  final close = target.close;
  final indent = _indentOf(vdf, close);
  final lineStart = close - indent.length;
  final inner = '$indent\t';
  final line = '$inner"LaunchOptions"\t\t${_quote(value)}\n';
  final text = app != null
      ? line
      : '$inner${_quote('$appid')}\n$inner{\n\t$line$inner}\n';
  if (indent.isEmpty && vdf.substring(target.open + 1, close).trim().isEmpty) {
    // `{}` on one line: no line of its own to put the entry on
    final flat = text.trim().replaceAll('\n', ' ');
    return vdf.replaceRange(close, close, ' $flat ');
  }
  return vdf.replaceRange(lineStart, lineStart, text);
}

/// [existing] launch options with MangoHud logging in front, or null when
/// they already use MangoHud (ours, or kuhy's own: not touched).
String? mangoOptions(String existing, String conf) {
  if (RegExp(r'(^|\s)(MANGOHUD\w*=|mangohud(\s|$))').hasMatch(existing)) {
    return null;
  }
  final path = conf.contains(' ') ? "'$conf'" : conf;
  final mango = 'MANGOHUD=1 MANGOHUD_CONFIGFILE=$path';
  final rest = existing.trim();
  if (rest.isEmpty) return '$mango %command%';
  return rest.contains('%command%') ? '$mango $rest' : '$mango %command% $rest';
}

/// What [addMangoHud] did: `added`, `present` (ours already there) or
/// `user mangohud` (kuhy's own MangoHud option, left alone).
typedef MangoEdit = ({String text, String result});

/// Adds the MangoHud logging option for [appid] to [vdf], idempotently.
MangoEdit addMangoHud(String vdf, int appid, String conf) {
  final existing = launchOption(vdf, appid) ?? '';
  final next = mangoOptions(existing, conf);
  if (next == null) {
    final ours =
        existing.contains('MANGOHUD_CONFIGFILE=$conf') ||
        existing.contains("MANGOHUD_CONFIGFILE='$conf'");
    return (text: vdf, result: ours ? 'present' : 'user mangohud');
  }
  return (text: setLaunchOption(vdf, appid, next)!, result: 'added');
}
