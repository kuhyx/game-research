/// Crash-proof JSON files: a power cut leaves NUL bytes, a torn last line or a
/// half-written file (kuhy, 2026-11-11: the 23:10 shutdown tore two
/// `captions.jsonl`, and `--resume-all` crashed on them). Every reader here
/// treats damage as absent data, never as an exception; every whole-file
/// writer goes through [writeAtomic].
library;

import 'dart:convert';
import 'dart:io';

/// What a tolerant JSONL read found.
class JsonlRead {
  /// Creates a result.
  const new(
    this.rows,
    this.skipped, {
    this.terminated = true,
    this.hadNul = false,
  });

  /// The lines that decoded to a JSON object (and passed `accept`).
  final List<Map<String, Object?>> rows;

  /// How many non-blank lines were dropped.
  final int skipped;

  /// The text ended on a newline (or was empty): appending is safe.
  final bool terminated;

  /// NUL bytes were stripped.
  final bool hadNul;

  /// Nothing was dropped or repaired: the file is exactly [rows].
  bool get clean => skipped == 0 && terminated && !hadNul;
}

const _lenient = Utf8Decoder(allowMalformed: true);

String _decode(List<int> bytes) =>
    _lenient.convert(bytes.where((b) => b != 0).toList());

/// Reads JSONL [text]: blank lines are ignored; a line that is not a JSON
/// object, or that [accept] rejects (by returning false or throwing), is
/// counted in [JsonlRead.skipped] and dropped.
JsonlRead parseJsonl(
  String text, {
  bool Function(Map<String, Object?> row)? accept,
  bool hadNul = false,
}) {
  final rows = <Map<String, Object?>>[];
  var skipped = 0;
  for (final line in const LineSplitter().convert(text)) {
    if (line.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, Object?> &&
          (accept == null || accept(decoded))) {
        rows.add(decoded);
        continue;
      }
    } on Object {
      // torn or junk: counted below
    }
    skipped++;
  }
  return JsonlRead(
    rows,
    skipped,
    terminated: text.isEmpty || text.endsWith('\n'),
    hadNul: hadNul,
  );
}

/// [parseJsonl] over file [f] (NUL bytes stripped); a missing or unreadable
/// file reads as empty.
JsonlRead readJsonl(File f, {bool Function(Map<String, Object?> row)? accept}) {
  final List<int> bytes;
  try {
    bytes = f.readAsBytesSync();
  } on FileSystemException {
    return const JsonlRead([], 0);
  }
  return parseJsonl(_decode(bytes), accept: accept, hadNul: bytes.contains(0));
}

/// The decoded JSON of [f] (NUL bytes stripped); null when the file is
/// missing, unreadable or not valid JSON.
Object? readJson(File f) {
  try {
    return jsonDecode(_decode(f.readAsBytesSync()));
  } on Object {
    return null;
  }
}

/// The JSON object in [f]; null when missing, corrupt or not an object.
Map<String, Object?>? readJsonObject(File f) {
  final v = readJson(f);
  return v is Map<String, Object?> ? v : null;
}

/// Writes [text] to [f] through `<f>.tmp` and a rename: a power cut leaves
/// the old file or the new one, never half of either.
void writeAtomic(File f, String text) {
  f.parent.createSync(recursive: true);
  File('${f.path}.tmp')
    ..writeAsStringSync(text, flush: true)
    ..renameSync(f.path);
}

/// Atomically rewrites [f] as one line per row.
void writeJsonlAtomic(File f, Iterable<Map<String, Object?>> rows) =>
    writeAtomic(f, rows.map((r) => '${jsonEncode(r)}\n').join());
