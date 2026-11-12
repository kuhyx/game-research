/// Keeps Opus's documents under the target repo's 250-line cap: parse the
/// answer, and when a document is over, one follow-up call asks for a
/// shorter rewrite. A second overflow fails the stage closed.
library;

import 'dart:io';

import 'package:game_research/core/doc_cap.dart';

/// Parses [raw] with [parse]. [docs] names the documents of a parse result.
/// If any is over [kLineCap] lines, [raw] is saved to [longFile] and [shorten]
/// runs once with the follow-up prompt (it returns the new raw answer); the
/// result must fit now, else a [StateError] says which document is too long.
Future<R> parseWithinCap<R>({
  required String raw,
  required R Function(String raw) parse,
  required Map<String, String> Function(R parsed) docs,
  required File longFile,
  required String format,
  required Future<String> Function(String prompt) shorten,
}) async {
  Map<String, int> over(R parsed) => {
    for (final e in docs(parsed).entries)
      if (lineCount(e.value) > kLineCap) e.key: lineCount(e.value),
  };
  var parsed = parse(raw);
  final first = over(parsed);
  if (first.isEmpty) return parsed;
  longFile.writeAsStringSync(raw);
  parsed = parse(
    await shorten(
      shortenPrompt(longFile: longFile.path, over: first, format: format),
    ),
  );
  final second = over(parsed);
  if (second.isNotEmpty) {
    final what = second.entries.map((e) => '${e.key} has ${e.value} lines');
    throw StateError(
      '${what.join(', ')} after one shortening call (cap $kLineCap)',
    );
  }
  return parsed;
}
