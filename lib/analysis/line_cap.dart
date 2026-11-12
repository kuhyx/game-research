/// Holds Opus's documents to the line cap and the writing rules: parse the
/// answer, check it, and when anything is broken one follow-up call lists each
/// violation by name and asks for a rewrite. Any violation left after that one
/// call fails the stage closed.
library;

import 'dart:io';

import 'package:game_research/core/doc_cap.dart';

/// Builds the follow-up prompt of the rewrite (see [shortenPrompt], the
/// default): the long answer's file, each violation by name, the reply shape.
typedef ShortenPromptBuilder = String Function({
  required String longFile,
  required List<String> violations,
  required String format,
});

/// Parses [raw] with [parse]. [violations] lists the broken rules of a parse
/// result, each as a human-readable line (see `doc_cap.dart`). If there are
/// any, [raw] is saved to [longFile] and [shorten] runs once with the
/// follow-up prompt (it returns the new raw answer); the result must be clean
/// now, else a [StateError] names what is left. Never a second retry.
/// [promptFor] builds the follow-up prompt (default: [shortenPrompt]); [cap]
/// names the limit in the error.
Future<R> parseWithinCap<R>({
  required String raw,
  required R Function(String raw) parse,
  required List<String> Function(R parsed) violations,
  required File longFile,
  required String format,
  required Future<String> Function(String prompt) shorten,
  ShortenPromptBuilder promptFor = shortenPrompt,
  String cap = '$kLineCap lines',
}) async {
  var parsed = parse(raw);
  final first = violations(parsed);
  if (first.isEmpty) return parsed;
  longFile.writeAsStringSync(raw);
  parsed = parse(
    await shorten(
      promptFor(longFile: longFile.path, violations: first, format: format),
    ),
  );
  final left = violations(parsed);
  if (left.isNotEmpty) {
    throw StateError('${left.join(', ')} after one shortening call (cap $cap)');
  }
  return parsed;
}
