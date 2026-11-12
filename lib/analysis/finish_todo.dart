/// The todo task a finished game leaves behind: one task for the
/// todoImplementer board that applies the research to the target repo, with
/// a done check Opus proposed. Created through `GAME_RESEARCH_TODO_CMD`
/// (`dart run ~/src/todo/bin/todo_note.dart`).
library;

import 'package:game_research/core/finish_doc.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// `owner/name` of [target]'s `origin`. Throws when the remote is missing or
/// not a GitHub-style URL: the task would land in the wrong repo's board.
Future<String> targetRepo(Sys sys, String target) async {
  final remote = await sys.run('git', [
    '-C',
    target,
    'remote',
    'get-url',
    'origin',
  ]);
  final repo = repoFromRemote(remote.exitCode == 0 ? '${remote.stdout}' : null);
  if (repo == null) {
    throw StateError('cannot derive the repo slug from $target origin');
  }
  return repo;
}

/// Creates the task and returns its id. [body] and [check] come from Opus
/// (already checked non-empty and one line); the two document paths are
/// added here so the implementer finds the full report.
Future<String> createFinishTodo({
  required Config config,
  required Sys sys,
  required String repo,
  required String game,
  required String body,
  required String check,
  required String report,
  required String merged,
}) async {
  final cmd = config.todoCmd;
  final text =
      '${finishTodoTitle(game, repo)}\n\n$body\n\n'
      'Report: $report\nMerged answers: $merged';
  final r = await sys.run(cmd.first, [
    ...cmd.skip(1),
    '--repo',
    repo,
    '--new-note',
    '--by',
    'claude',
    '--done-check',
    check,
    '--text',
    text,
  ], workingDirectory: p.join(config.home, 'src', 'todo'));
  if (r.exitCode != 0) {
    throw StateError('todo task failed (${r.exitCode}): ${r.stderr}');
  }
  return '${r.stdout}'.trim();
}
