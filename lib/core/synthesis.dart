/// Stage 3: the one Opus call per session that fills the questions template.
///
/// Opus gets Read only. It answers both documents between marker lines
/// and the analyzer writes both files itself, so a malformed answer fails
/// closed instead of leaving a half-written draft in the target repo.
library;

import 'package:path/path.dart' as p;

/// The English draft and its Polish twin.
class Drafts {
  /// Creates the pair.
  const new(this.en, this.pl);

  /// English.
  final String en;

  /// Polish.
  final String pl;
}

/// The marker lines around the two documents in Opus's answer. Plain lines,
/// not JSON: ~450 lines of markdown inside JSON strings is where escaping
/// breaks, and every broken answer costs another Opus call.
const kEnMarker = '@@@EN';

/// See [kEnMarker].
const kPlMarker = '@@@PL';

/// See [kEnMarker].
const kEndMarker = '@@@END';

String _doc(List<String> lines, String name) {
  final text = lines.join('\n').trim();
  if (!text.startsWith('# ')) {
    throw FormatException('synthesis $name doc is missing or not a doc');
  }
  return '$text\n';
}

/// The two documents in Opus's answer [raw]: the lines between `@@@EN`,
/// `@@@PL` and `@@@END`, each on its own line, in that order. Throws when a
/// marker is missing or out of order, or a doc is empty or lacks a `# `
/// heading.
Drafts parseSynthesis(String raw) {
  final lines = raw.split('\n').map((l) => l.trimRight()).toList();
  final en = lines.indexOf(kEnMarker);
  final pl = lines.indexOf(kPlMarker);
  final end = lines.indexOf(kEndMarker);
  if (en < 0 || pl <= en || end <= pl) {
    throw const FormatException('synthesis answer lacks @@@EN/@@@PL/@@@END');
  }
  return Drafts(
    _doc(lines.sublist(en + 1, pl), 'en'),
    _doc(lines.sublist(pl + 1, end), 'pl'),
  );
}

/// The template pair inside a target repo.
Drafts templatePaths(String targetRoot) {
  final dir = p.join(targetRoot, 'docs', 'research');
  return Drafts(
    p.join(dir, 'DOCS-research-questions.md'),
    p.join(dir, 'DOCS-research-questions-pl.md'),
  );
}

/// Where the drafts for [gameSlug] go inside [targetRoot].
Drafts draftPaths(String targetRoot, String gameSlug) {
  final dir = p.join(targetRoot, 'docs', 'research');
  return Drafts(
    p.join(dir, 'DOCS-research-$gameSlug.md'),
    p.join(dir, 'DOCS-research-$gameSlug-pl.md'),
  );
}

/// The todo task's title. Reviewing is kuhy's manual work, and todoImplementer
/// never runs a task titled `MANUAL WORK REQUIRED:` (cleanup-plate gets no
/// Claude-runnable tasks).
String todoTaskTitle(String game) =>
    'MANUAL WORK REQUIRED: review $game research draft';

/// The task's done check: the reviewed draft is committed in the target.
String todoDoneCheck(String gameSlug) =>
    'git ls-files --error-unmatch docs/research/DOCS-research-$gameSlug.md';

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
  required String templateEn,
  required String templatePl,
  required String captions,
  required String markers,
  required String stills,
  required List<String> frames,
}) =>
    '''
You are a game-design researcher. kuhy played "$game" (session $session)
as research for his own game. Fill his questions template from the evidence.

Read these files with the Read tool:
- English template: $templateEn
- Polish twin of the template: $templatePl
- Captions of sampled frames (JSONL: frame, t seconds, caption): $captions
- kuhy's markers (JSONL: offset_s, tag good|bad|confusing|note, note): $markers
- Stretches with no motion over the threshold (JSONL: start_s, end_s): $stills
- Frames to look at (marker frames first, at most 60 per hour):
${frames.map((f) => '  - $f').join('\n')}

Rules:
- Keep every heading, question id and "Why we ask" line of the template.
- Replace {{GAME}} with "$game", {{SESSION}} with "$session", and every
  _(pending)_ with your answer. Answer from the evidence only; when the
  session shows nothing for a question, say so plainly.
- Evidence cites marker offsets as mm:ss and frame file names.
- Markers are kuhy's own judgement: weigh "bad" and "confusing" heavily.
- Under "Open threads" list what the session raised that no question covers.
- The Polish document is a faithful Polish version of the English one.

Reply with exactly this and nothing else, each marker alone on its line:
$kEnMarker
<the filled English markdown>
$kPlMarker
<the filled Polish markdown>
$kEndMarker
''';
