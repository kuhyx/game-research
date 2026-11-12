/// The 250-line cap of the target repo (cleanup-plate's file-length gate caps
/// every `.md` there) and what keeps Opus's documents under it: the code tidies
/// the answer, counts the lines, and asks once for a shorter rewrite.
library;

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

/// The follow-up prompt that asks for [over] (document name -> lines) to be
/// rewritten shorter. The model keeps no memory between calls, so its
/// previous answer is a file: [longFile]. [format] is the reply shape.
String shortenPrompt({
  required String longFile,
  required Map<String, int> over,
  required String format,
}) =>
    '''
Your previous answer is too long for the target repo's $kLineCap-line file
cap. Read it with the Read tool: $longFile

Too long: ${over.entries.map((e) => '${e.key} (${e.value} lines)').join(', ')}.

Rewrite the whole answer so that every document has at most $kShortenTo
lines. Keep every heading, question id and `- **Status:**` line, and no
blank line between questions; shorten evidence and answers instead of
dropping a question. Do not add anything new.

Reply with exactly this and nothing else, each marker alone on its line:
$format
''';
