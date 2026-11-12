/// The 250-line cap of the target repo (cleanup-plate's file-length gate caps
/// every `.md` there), the writing-rule caps on top of it, and what keeps
/// Opus's documents inside both: the code tidies the answer, lists every
/// violation by name, and asks once for a rewrite.
library;

import 'package:game_research/core/doc_refs.dart';
import 'package:game_research/core/doc_rules.dart';

/// Lines a written document may have at most.
const kLineCap = 250;

/// The length a shortening call is asked for: headroom under [kLineCap].
const kShortenTo = 240;

final _blankRuns = RegExp(r'\n{3,}');
final _whyWeAsk = RegExp(r'^Why we ask:.*\n?', multiLine: true);

/// [doc] without the template's `Why we ask:` lines (they stay in the
/// template) and with every run of blank lines cut to one.
String tidyDoc(String doc) =>
    doc.replaceAll(_whyWeAsk, '').replaceAll(_blankRuns, '\n\n').trim();

/// How many lines the file holding [doc] has.
int lineCount(String doc) => doc.isEmpty
    ? 0
    : '\n'.allMatches(doc.endsWith('\n') ? doc : '$doc\n').length;

/// The line cap break of [doc] (`draft: 301 lines > 250`), else none. [name]
/// names the document.
List<String> lineViolations(String name, String doc) {
  final n = lineCount(doc);
  return n > kLineCap ? ['$name: $n lines > $kLineCap'] : const [];
}

/// Every break in a document of questions: the line cap, then the question
/// rules ([questionViolations]).
List<String> docViolations(String name, String doc) => [
  ...lineViolations(name, doc),
  ...questionViolations(doc),
];

/// Every break in the report: the line cap, then the word cap.
List<String> reportViolations(String report) {
  final words = proseWords(report);
  return [
    ...lineViolations('report', report),
    if (words > kReportWordCap) 'report: $words words > $kReportWordCap',
  ];
}

/// The follow-up prompt that asks for a rewrite without [violations] (each
/// one a line such as `Q1.1 Answer 31 > 22`). The model keeps no memory
/// between calls, so its previous answer is a file: [longFile]. [format] is
/// the reply shape.
String shortenPrompt({
  required String longFile,
  required List<String> violations,
  required String format,
}) =>
    '''
Your previous answer breaks the rules of the research documents. Read it
with the Read tool: $longFile

Broken, each by name:
${violations.map((v) => '- $v').join('\n')}

Rewrite the whole answer so that none of these is left. Every document has
at most $kShortenTo lines (the target repo's $kLineCap-line cap). Keep every
heading id, question id and `- **Status:**` line, and no blank line between
questions; shorten answers and evidence instead of dropping a question. Do
not add anything new.

$kWritingRules
- A report has at most $kReportWordCap prose words in all, quotes included.

Reply with exactly this and nothing else, each marker alone on its line:
$format
''';
