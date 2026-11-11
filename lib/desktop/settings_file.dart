/// `<dataDir>/settings.json`: the picked target and the last game.
/// Every writer merges, so one key never wipes another.
library;

import 'dart:convert';
import 'dart:io';

/// The settings object on disk.
class SettingsFile {
  /// Wraps [path].
  const new(this.path);

  /// The JSON file.
  final String path;

  /// The stored object; `{}` when missing or corrupt.
  Map<String, Object?> read() {
    final f = File(path);
    if (!f.existsSync()) return {};
    try {
      final v = jsonDecode(f.readAsStringSync());
      return v is Map<String, Object?> ? v : {};
    } on FormatException {
      return {};
    }
  }

  /// Sets [values] and keeps every other key.
  void merge(Map<String, Object?> values) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({...read(), ...values}));
  }
}
