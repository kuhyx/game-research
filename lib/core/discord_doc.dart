/// The short Discord version of a research document: kuhy pastes it as one
/// free-Discord message (2000 characters; the cap here is 1900). It sits next
/// to its document as `X.discord.md`, which `priorDrafts` never takes for a
/// session draft (its name needs `-<stamp>.md` right after the slug). Opus
/// answers between marker lines like every other document; code checks the
/// answer ([discordViolations]) and never the model (fail closed).
library;

import 'package:game_research/core/doc_cap.dart';
import 'package:game_research/core/synthesis.dart';

/// The marker line before the short version (it ends at `@@@END`).
const kDiscordMarker = '@@@DISCORD';

/// Most characters ([String.length]) a short version may have.
const kDiscordMax = 1900;

/// The length the prompt asks for: headroom under [kDiscordMax].
const kDiscordAim = 1800;

const _suffix = '.discord.md';

/// Whether [path] is a short version.
bool isDiscordPath(String path) => path.endsWith(_suffix);

/// The short version's path next to the document [docPath]: `X.md` becomes
/// `X.discord.md`. Throws [ArgumentError] for a non-`.md` path or a path that
/// already is a short version.
String discordPathOf(String docPath) {
  if (!docPath.endsWith('.md') || isDiscordPath(docPath)) {
    throw ArgumentError.value(docPath, 'docPath', 'needs a plain .md file');
  }
  return '${docPath.substring(0, docPath.length - 3)}$_suffix';
}

const _rules =
    '''
Discord markdown only, as ONE message of at most $kDiscordMax characters
(aim for $kDiscordAim; count every character, spaces and newlines included):
- `#`, `##` and `###` headings only, never `####` or deeper.
- **bold** and `-` lists; no tables, no `|` rows, no HTML.
- Keep the key findings: what the doc concludes and what to do with it.
  Evidence references (frame files, mm:ss, stamps) are not needed.''';

/// The first prompt. Paths only: Opus reads [docPath] with its Read tool.
String buildDiscordPrompt(String docPath) =>
    '''
Compact a research document into a short version kuhy pastes into Discord.

Read it with the Read tool: $docPath

$_rules

Reply with exactly this and nothing else, each marker alone on its line:
$kDiscordMarker
<the short markdown>
$kEndMarker
''';

/// The follow-up prompt for a rewrite without [violations]; it plugs into
/// `parseWithinCap` as its prompt builder. The previous answer is the file
/// [longFile] (the model keeps no memory between calls).
String discordRewritePrompt({
  required String docPath,
  required String longFile,
  required List<String> violations,
  required String format,
}) =>
    '''
Your previous short version breaks the rules. Read it with the Read tool:
$longFile
The document it summarises: $docPath

Broken, each by name:
${violations.map((v) => '- $v').join('\n')}

Rewrite it so that none of these is left.

$_rules

Reply with exactly this and nothing else, each marker alone on its line:
$format
''';

/// The short version in Opus's answer [raw]: the lines between `@@@DISCORD`
/// and `@@@END`, tidied. Throws when a marker is missing; an empty section is
/// returned empty, for [discordViolations] to name.
String parseDiscord(String raw) {
  final lines = raw.split('\n').map((l) => l.trimRight()).toList();
  final start = lines.indexOf(kDiscordMarker);
  if (start < 0) throw const FormatException('answer lacks $kDiscordMarker');
  final end = lines.indexWhere((l) => l == kEndMarker, start + 1);
  if (end < 0) throw const FormatException('answer lacks $kEndMarker');
  return tidyDoc(lines.sublist(start + 1, end).join('\n'));
}

final _tableRow = RegExp(r'^\s*\|');
final _deepHeading = RegExp(r'^\s*#{4,}(\s|$)');

/// Every rule [text] breaks, each by name: empty, over [kDiscordMax]
/// characters, table rows, headings deeper than `###`.
List<String> discordViolations(String text) {
  if (text.trim().isEmpty) return const ['discord: empty'];
  final lines = text.split('\n');
  List<int> at(RegExp re) => [
    for (var i = 0; i < lines.length; i++)
      if (re.hasMatch(lines[i])) i + 1,
  ];
  final tables = at(_tableRow);
  final deep = at(_deepHeading);
  return [
    if (text.length > kDiscordMax)
      'discord: ${text.length} chars > $kDiscordMax',
    if (tables.isNotEmpty) 'discord: table rows at lines ${tables.join(', ')}',
    if (deep.isNotEmpty)
      'discord: heading deeper than ### at lines ${deep.join(', ')}',
  ];
}
