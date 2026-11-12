/// "Research finished" for one game: one Opus call merges every session
/// draft into the merged answers and writes a report kuhy reads. Plain
/// marker lines like stage 3, checked by code; English only.
library;

import 'package:game_research/core/synthesis.dart';

/// The marker line before the merged answers.
const kMergedMarker = '@@@MERGED';

/// The marker line before the report.
const kReportMarker = '@@@REPORT';

/// A session's draft (or markers file) with the session stamp it belongs to.
typedef StampedPath = ({String stamp, String path});

/// The merged answers and the report in Opus's answer [raw]. Every question
/// of [template] must carry one valid status line in the merged answers.
({String merged, String report}) parseFinish(String raw, {String? template}) {
  final merged = sliceDoc(raw, kMergedMarker, [kReportMarker]);
  if (template != null) checkStatusLines(merged, template);
  return (merged: merged, report: sliceDoc(raw, kReportMarker, [kEndMarker]));
}

/// The todo task's title for the report review.
String finishTodoTitle(String game) =>
    'MANUAL WORK REQUIRED: review $game research report';

/// The task's done check: the reviewed report is committed in the target.
String finishDoneCheck(String gameSlug) =>
    'git ls-files --error-unmatch '
    'docs/research/games/$gameSlug/DOCS-research-$gameSlug-report.md';

/// The merge prompt. Paths only: Opus reads the files with its Read tool.
String buildFinishPrompt({
  required String game,
  required String template,
  required List<StampedPath> drafts,
  required List<StampedPath> markers,
}) =>
    '''
You are a game-design researcher. kuhy finished researching "$game" for his
own game over ${drafts.length} play session(s). Merge what he learned.

Read these files with the Read tool:
- Questions template: $template
- Session drafts, oldest first (each answers the template for one session):
${drafts.map((d) => '  - ${d.stamp}: ${d.path}').join('\n')}
- kuhy's markers per session (JSONL: offset_s, tag good|bad|confusing|note,
  note), where his own notes are:
${markers.map((m) => '  - ${m.stamp}: ${m.path}').join('\n')}

Write two English documents.

1. MERGED ANSWERS: the template filled in once. Keep every heading and
   question id; do NOT copy the "Why we ask:" lines (they stay in the
   template). For each question take the best-supported
   answer across the drafts; a later session wins only with new evidence.
   Evidence cites the session stamp and the marker offset (mm:ss) or frame
   file. Directly after each Answer line add exactly one line
   `- **Status:** answered`, `- **Status:** partial` or `- **Status:** open`
   (answered if any draft settled it, partial if only partial, else open).

2. REPORT: a human-readable report for kuhy, starting with a `# ` heading,
   with these sections: What $game does well; What it does badly; What
   confused kuhy (quote his notes verbatim with session stamp and mm:ss);
   What cleanup-plate should copy; What cleanup-plate should avoid; Open
   questions (the questions still open or partial, one line each).

Each file stays at 250 lines or fewer (the target repo's commit gate): keep
evidence short rather than dropping a question.

Reply with exactly this and nothing else, each marker alone on its line:
$kMergedMarker
<the merged markdown>
$kReportMarker
<the report markdown>
$kEndMarker
''';
