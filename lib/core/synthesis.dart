/// Stage 3: the one Opus call per session that fills the questions template.
///
/// Opus gets Read only. It answers the document between marker lines and the
/// analyzer writes the file itself, so a malformed answer fails closed instead
/// of leaving a half-written draft in the target repo. Each session writes its
/// own draft, never overwriting an earlier one; the prompt carries the earlier
/// drafts so settled questions are copied forward and only open ones are
/// re-answered. English only (kuhy, 2026-11-12).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// A pair of paths. Only `en` is used any more; the pair stays because
/// `templatePaths(...).en` is how the wrapper finds a target repo.
class Drafts {
  /// Creates the pair.
  const new(this.en, this.pl);

  /// English.
  final String en;

  /// Polish twin of the template (no longer read or written).
  final String pl;
}

/// The marker line before the document in Opus's answer. Plain lines, not
/// JSON: ~450 lines of markdown inside JSON strings is where escaping breaks,
/// and every broken answer costs another Opus call.
const kDocMarker = '@@@DOC';

/// The marker line after the document (and after the last of several).
const kEndMarker = '@@@END';

/// The `- **Status:**` line every question carries.
final statusLine = RegExp(
  r'^- \*\*Status:\*\* (answered|partial|open)\s*$',
  multiLine: true,
);

final _questionHead = RegExp(r'^### (Q\d+(?:\.\d+)*)\b', multiLine: true);

/// The question ids (`Q1.1`) of a template or draft, in order.
List<String> questionIds(String doc) => [
  for (final m in _questionHead.allMatches(doc)) m.group(1)!,
];

/// Throws unless every question of [template] is in [doc] with exactly one
/// valid status line. Code adjudicates, not the model (fail closed).
void checkStatusLines(String doc, String template) {
  final ids = questionIds(template);
  final heads = _questionHead.allMatches(doc).toList();
  for (final id in ids) {
    final at = heads.indexWhere((m) => m.group(1) == id);
    if (at < 0) throw FormatException('draft lacks question $id');
    final end = at + 1 < heads.length ? heads[at + 1].start : doc.length;
    final n = statusLine.allMatches(doc.substring(heads[at].start, end)).length;
    if (n != 1) throw FormatException('question $id has $n status lines');
  }
}

/// The lines of [raw] between the marker [from] and the next marker among
/// [until], as a document. Throws when a marker is missing or out of order,
/// or the document is empty or lacks a `# ` heading.
String sliceDoc(String raw, String from, List<String> until) {
  final lines = raw.split('\n').map((l) => l.trimRight()).toList();
  final start = lines.indexOf(from);
  if (start < 0) throw FormatException('synthesis answer lacks $from');
  var end = -1;
  for (var i = start + 1; i < lines.length && end < 0; i++) {
    if (until.contains(lines[i])) end = i;
  }
  if (end < 0) throw FormatException('synthesis answer lacks ${until.first}');
  final text = lines.sublist(start + 1, end).join('\n').trim();
  if (!text.startsWith('# ')) {
    throw FormatException('synthesis $from doc is missing or not a doc');
  }
  return '$text\n';
}

/// The document in Opus's answer [raw]: the lines between `@@@DOC` and
/// `@@@END`. When [template] is given, every question must carry one valid
/// status line ([checkStatusLines]).
String parseDoc(String raw, {String? template}) {
  final doc = sliceDoc(raw, kDocMarker, [kEndMarker]);
  if (template != null) checkStatusLines(doc, template);
  return doc;
}

/// The questions template inside a target repo.
String templatePath(String targetRoot) =>
    p.join(targetRoot, 'docs', 'research', 'DOCS-research-questions.md');

/// The template pair inside a target repo (see [Drafts]).
Drafts templatePaths(String targetRoot) => Drafts(
  templatePath(targetRoot),
  p.join(targetRoot, 'docs', 'research', 'DOCS-research-questions-pl.md'),
);

/// `20261112-090025` from a session folder name like
/// `20261112-090025-some-game`; any other name is returned whole.
String sessionStamp(String dirName) =>
    RegExp(r'^\d{8}-\d{6}').firstMatch(dirName)?.group(0) ?? dirName;

/// `<target>/docs/research/games/<slug>`: every document of one game.
String gameDocsDir(String targetRoot, String gameSlug) =>
    p.join(targetRoot, 'docs', 'research', 'games', gameSlug);

/// One session's draft. Never overwritten by a later session.
String draftPath(String targetRoot, String gameSlug, String stamp) => p.join(
  gameDocsDir(targetRoot, gameSlug),
  'DOCS-research-$gameSlug-$stamp.md',
);

/// The merged answers of a finished game.
String mergedPath(String targetRoot, String gameSlug) =>
    p.join(gameDocsDir(targetRoot, gameSlug), 'DOCS-research-$gameSlug.md');

/// The human-readable report of a finished game.
String reportPath(String targetRoot, String gameSlug) => p.join(
  gameDocsDir(targetRoot, gameSlug),
  'DOCS-research-$gameSlug-report.md',
);

/// The session drafts of [gameSlug] in the target, oldest first, leaving out
/// [exceptStamp] (the session being written). Only
/// `DOCS-research-<slug>-<stamp>.md` counts: not the merged file, not the
/// report, not the flat v1 drafts of the old layout.
List<String> priorDrafts(
  String targetRoot,
  String gameSlug, {
  String? exceptStamp,
}) {
  final dir = Directory(gameDocsDir(targetRoot, gameSlug));
  if (!dir.existsSync()) return const [];
  final name = RegExp(
    '^DOCS-research-${RegExp.escape(gameSlug)}-(\\d{8}-\\d{6})\\.md\$',
  );
  final found = <(String, String)>[];
  for (final f in dir.listSync().whereType<File>()) {
    final stamp = name.firstMatch(p.basename(f.path))?.group(1);
    if (stamp != null && stamp != exceptStamp) found.add((stamp, f.path));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

/// The todo task's title. Reviewing is kuhy's manual work, and todoImplementer
/// never runs a task titled `MANUAL WORK REQUIRED:` (cleanup-plate gets no
/// Claude-runnable tasks).
String todoTaskTitle(String game) =>
    'MANUAL WORK REQUIRED: review $game research draft';

/// The task's done check: the reviewed session draft is committed.
String todoDoneCheck(String gameSlug, String stamp) =>
    'git ls-files --error-unmatch '
    'docs/research/games/$gameSlug/DOCS-research-$gameSlug-$stamp.md';

/// `kuhyx/<repo name>` from a git [remote] URL, else from [dirName]: todo
/// tasks are keyed by kuhy's repo slug whoever owns the origin.
String repoSlugFromRemote(String? remote, String dirName) {
  final url = remote?.trim() ?? '';
  if (url.isEmpty) return 'kuhyx/$dirName';
  final last = url.split(RegExp('[/:]')).last;
  return 'kuhyx/${last.endsWith('.git') ? last.substring(0, last.length - 4) : last}';
}

/// The synthesis prompt. Paths only: Opus reads the files with its Read tool.
String buildSynthesisPrompt({
  required String game,
  required String session,
  required String template,
  required List<String> earlier,
  required String captions,
  required String markers,
  required String stills,
  required List<String> frames,
}) =>
    '''
You are a game-design researcher. kuhy played "$game" (session $session)
as research for his own game. Fill his questions template from the evidence.

Read these files with the Read tool:
- Questions template: $template
- Earlier session drafts of this game, oldest first:
${earlier.isEmpty ? '  (none: this is the first session)' : earlier.map((f) => '  - $f').join('\n')}
- Captions of sampled frames (JSONL: frame, t seconds, caption): $captions
- kuhy's markers (JSONL: offset_s, tag good|bad|confusing|note, note): $markers
- Stretches with no motion over the threshold (JSONL: start_s, end_s): $stills
- Frames to look at (marker frames first, at most 60 per hour):
${frames.map((f) => '  - $f').join('\n')}

Rules:
- Write ONE English document: the template filled in. Keep every heading,
  question id and "Why we ask" line. Replace {{GAME}} with "$game",
  {{SESSION}} with "$session", and every _(pending)_ with your answer.
- Directly after each question's Answer line add exactly one line
  `- **Status:** answered`, `- **Status:** partial` or `- **Status:** open`
  (answered: the evidence settles it; partial: some evidence, gaps remain;
  open: nothing yet). Every question gets one.
- Earlier drafts: copy forward, unchanged, the Answer, Evidence, For
  cleanup-plate and Status of every question an earlier draft marked
  answered, unless this session has new evidence on it. Re-answer only the
  questions that are open or partial, or where this session adds evidence;
  then keep the earlier evidence that still holds and add this session's.
- Answer from the evidence only; when nothing shows for a question, say so.
- Evidence cites marker offsets as mm:ss and frame file names.
- Markers are kuhy's own judgement: weigh "bad" and "confusing" heavily and
  quote his notes verbatim.
- Under "Open threads" list what the session raised that no question covers.
- The file stays at 250 lines or fewer (the target repo's commit gate): drop
  the blank lines between questions and keep evidence short rather than
  dropping a question.

Reply with exactly this and nothing else, each marker alone on its line:
$kDocMarker
<the filled English markdown>
$kEndMarker
''';
