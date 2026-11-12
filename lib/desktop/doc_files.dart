/// Reading and saving the research drafts and reports from the panel.
///
/// The panel passes an absolute path; only existing `.md` files that really
/// live (symlinks resolved) under `<target>/docs/research/` of a known
/// target may be read or replaced. Anything else is [DocDenied].
library;

import 'dart:io';

import 'package:game_research/core/discord_doc.dart';
import 'package:path/path.dart' as p;

/// Largest file the panel reads or writes.
const int kDocMaxBytes = 1024 * 1024;

/// The path is not an allowed document (403).
class DocDenied implements Exception {
  /// Creates the error.
  const new(this.message);

  /// Why.
  final String message;

  @override
  String toString() => message;
}

/// The path is allowed but no file is there (404).
class DocMissing implements Exception {
  /// Creates the error.
  const new();

  @override
  String toString() => 'no such document';
}

/// Guarded access to `<target>/docs/research/**.md`.
class DocFiles {
  /// [targets] lists the target project folders.
  const new(this.targets);

  /// The known target folders (re-read on every call).
  final List<String> Function() targets;

  /// The canonical path of [path], when allowed and present.
  String _allowed(String path) {
    if (!p.isAbsolute(path)) throw const DocDenied('absolute path needed');
    if (p.extension(path) != '.md') throw const DocDenied('only .md files');
    final wanted = p.normalize(path);
    for (final target in targets()) {
      final root = p.join(target, 'docs', 'research');
      if (!p.isWithin(root, wanted)) continue;
      final file = File(wanted);
      if (!file.existsSync()) throw const DocMissing();
      final real = file.resolveSymbolicLinksSync();
      final realRoot = Directory(root).resolveSymbolicLinksSync();
      if (!p.isWithin(realRoot, real)) {
        throw const DocDenied('outside docs/research');
      }
      return real;
    }
    throw const DocDenied('outside docs/research');
  }

  /// The text of [path].
  String read(String path) {
    final real = _allowed(path);
    if (File(real).lengthSync() > kDocMaxBytes) {
      throw const DocDenied('too large');
    }
    return File(real).readAsStringSync();
  }

  /// The text of the Discord version next to document [path] (`X.md` ->
  /// `X.discord.md`), null when there is none or it may not be read. Throws
  /// like [read] when [path] itself is not allowed.
  String? readShort(String path) {
    _allowed(path);
    if (isDiscordPath(path)) return null;
    try {
      return read(discordPathOf(path));
    } on DocMissing {
      return null;
    } on DocDenied {
      return null;
    }
  }

  /// Replaces the text of the existing document [path]. Its Discord version
  /// describes the old text, so it is deleted (kuhy's own edit of a Discord
  /// version is kept).
  void write(String path, String text) {
    final real = _allowed(path);
    if (text.length > kDocMaxBytes) throw const DocDenied('too large');
    File(real).writeAsStringSync(text, flush: true);
    if (isDiscordPath(real)) return;
    final stale = File(discordPathOf(real));
    if (stale.existsSync()) stale.deleteSync();
  }
}
