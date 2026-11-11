/// Reading `claude -p --output-format json` output.
///
/// The exit code alone is not trusted: a usage-limit notice can come back
/// with exit 0. The envelope's `is_error` and `subtype` decide.
library;

import 'dart:convert';

/// The verdict on one `claude -p` run.
class ClaudeAnswer {
  const new _(this.text, this.reason, [this.model]);

  /// The model that answered (`modelUsage`'s first key), when reported.
  final String? model;

  /// The result text ('' when not [ok]).
  final String text;

  /// Why it failed (null when [ok]).
  final String? reason;

  /// Whether Claude answered.
  bool get ok => reason == null;
}

/// The answer in [stdout]: the last line holding a JSON object with a
/// `result`, accepted only with `subtype: success` and `is_error` false.
ClaudeAnswer readClaudeEnvelope(String stdout) {
  Map<Object?, Object?>? envelope;
  for (final line in [stdout, ...const LineSplitter().convert(stdout)]) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map && decoded.containsKey('subtype')) envelope = decoded;
    } on FormatException {
      continue;
    }
  }
  if (envelope == null) {
    final head = stdout.trim();
    return ClaudeAnswer._(
      '',
      'no JSON envelope: ${head.length > 200 ? head.substring(0, 200) : head}',
    );
  }
  final result = envelope['result'];
  if (envelope['is_error'] == true ||
      envelope['subtype'] != 'success' ||
      result is! String) {
    return ClaudeAnswer._(
      '',
      'claude ${envelope['subtype']}: ${result ?? 'no result'}',
    );
  }
  final usage = envelope['modelUsage'];
  final model = usage is Map && usage.isNotEmpty ? '${usage.keys.first}' : null;
  return ClaudeAnswer._(result, null, model);
}
