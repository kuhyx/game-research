/// `<dataDir>/settings.json`: the picked target and the last game.
/// Every writer merges, so one key never wipes another.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/safe_json.dart';

/// The settings object on disk.
class SettingsFile {
  /// Wraps [path].
  const new(this.path);

  /// The JSON file.
  final String path;

  /// The stored object; `{}` when missing or corrupt.
  Map<String, Object?> read() {
    return readJsonObject(File(path)) ?? {};
  }

  /// Sets [values] and keeps every other key.
  void merge(Map<String, Object?> values) {
    writeAtomic(File(path), jsonEncode({...read(), ...values}));
  }
}
