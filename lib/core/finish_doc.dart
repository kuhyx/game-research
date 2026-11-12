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

/// The marker line before the todo task's body.
const kTaskMarker = '@@@TASK';

/// The marker line before the todo task's done check.
const kCheckMarker = '@@@CHECK';

/// Everything Opus's answer holds: the two documents and the todo task.
typedef FinishAnswer = ({
  String merged,
  String report,
  String task,
  String check,
});

/// The trimmed, non-empty lines of [raw] between marker [from] and the next
/// marker among [until]. Throws when a marker is missing or the text empty.
String sliceText(String raw, String from, List<String> until) {
  final lines = raw.split('\n').map((l) => l.trimRight()).toList();
  final start = lines.indexOf(from);
  if (start < 0) throw FormatException('finish answer lacks $from');
  final end = lines.indexWhere(until.contains, start + 1);
  if (end < 0) throw FormatException('finish answer lacks ${until.first}');
  final text = lines.sublist(start + 1, end).join('\n').trim();
  if (text.isEmpty) throw FormatException('finish $from section is empty');
  return text;
}

/// The merged answers, the report, the task body and its done check in
/// Opus's answer [raw]. Every question of [template] must carry one valid
/// status line in the merged answers; the done check is one line.
FinishAnswer parseFinish(String raw, {String? template}) {
  final merged = sliceDoc(raw, kMergedMarker, [kReportMarker]);
  if (template != null) checkStatusLines(merged, template);
  final check = sliceText(raw, kCheckMarker, [kEndMarker]);
  if (check.contains('\n')) {
    throw const FormatException('finish done check is not a single line');
  }
  return (
    merged: merged,
    report: sliceDoc(raw, kReportMarker, [kTaskMarker]),
    task: sliceText(raw, kTaskMarker, [kCheckMarker]),
    check: check,
  );
}

/// `owner/name` of a GitHub remote URL (https or scp style), null when the
/// remote is missing or not that shape. The todo task needs the real repo.
String? repoFromRemote(String? remote) {
  final url = remote?.trim() ?? '';
  if (url.startsWith('/') || url.startsWith('.')) return null; // a path
  final parts = url.split(RegExp('[/:]')).where((s) => s.isNotEmpty).toList();
  if (parts.length < 2) return null;
  var name = parts.last;
  if (name.endsWith('.git')) name = name.substring(0, name.length - 4);
  final owner = parts[parts.length - 2];
  final ok = RegExp(r'^[A-Za-z0-9_.-]+$');
  if (!ok.hasMatch(owner) || !ok.hasMatch(name)) return null;
  return '$owner/$name';
}

/// The todoImplementer task's title (its first line).
String finishTodoTitle(String game, String repo) =>
    'Apply $game research to ${repo.split('/').last}';

/// The merge prompt. Paths only: Opus reads the files with its Read tool.
String buildFinishPrompt({
  required String game,
  required String target,
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

Write two English documents, then a task and a check.

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

3. TASK: the body of one todo task for an implementer agent who works in
   the target repo ($target) and has not read the report: the do and avoid
   list for that repo from the report, each item with its evidence (session
   stamp and mm:ss, or frame file). Plain text, no title line.

4. CHECK: exactly one shell command line that verifies the change in the
   target repo ($target). Read the target repo's CLAUDE.md and README.md
   first and use the test command they name (for example a Godot test run);
   do not invent a command.

Each file stays at 250 lines or fewer (the target repo's commit gate): keep
evidence short rather than dropping a question.

Reply with exactly this and nothing else, each marker alone on its line:
$kMergedMarker
<the merged markdown>
$kReportMarker
<the report markdown>
$kTaskMarker
<the task body>
$kCheckMarker
<the one-line check command>
$kEndMarker
''';
