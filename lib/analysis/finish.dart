/// "Research finished" for one game (`game_research_analyze --finish <slug>`):
/// one Opus call merges every analysed session draft into
/// `DOCS-research-<slug>.md` and writes `DOCS-research-<slug>-report.md` for
/// kuhy, then one todo task asks him to review the report. State lives in
/// `<data>/games/<slug>/finish.json` and `status.json` (same shape as a
/// session job's). Resumable and waiting like a session job.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/analysis/finish_sessions.dart';
import 'package:game_research/analysis/job.dart';
import 'package:game_research/analysis/tiers.dart';
import 'package:game_research/core/captions.dart';
import 'package:game_research/core/finish_doc.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:game_research/core/usage.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/recording_flag.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

export 'package:game_research/analysis/finish_sessions.dart';

/// Runs the finish job of one game.
class FinishRunner {
  /// Creates the runner.
  new(
    this.slug,
    this.config,
    this.sys, {
    this.ownerPid,
    this.recordingPoll = const Duration(seconds: 5),
  });

  /// Game slug.
  final String slug;

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  /// The lock owner's pid; defaults to this process.
  final int? ownerPid;

  /// How often a job paused by a recording checks again.
  final Duration recordingPoll;

  String get _dir => gameStateDir(config.dataDir, slug);
  File get _finish => File(p.join(_dir, 'finish.json'));

  Map<String, Object?> _read() => _finish.existsSync()
      ? jsonDecode(_finish.readAsStringSync()) as Map<String, Object?>
      : <String, Object?>{};

  void _write(Map<String, Object?> s) =>
      _finish.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(s));

  Usage _usage() {
    final s = _read();
    return Usage.fromJson({
      ...?(s['tokens'] as Map?)?.cast<String, Object?>(),
      'cost_usd': s['cost_usd'],
    });
  }

  Future<TierResult> _ask(String prompt, String file, List<String> dirs) {
    if (config.fakeLlm.isNotEmpty) {
      return FakeTier(config, sys, 'opus').call(file);
    }
    return ClaudeTier(
      config,
      sys,
      model: 'opus',
      limitS: 1500,
    ).ask(prompt, dirs);
  }

  /// Merges and reports. Returns the exit code ([JobExit]).
  Future<int> run() async {
    final sessions = analysedSessions(config.dataDir, slug);
    Directory(_dir).createSync(recursive: true);
    final status = StatusWriter(File(p.join(_dir, 'status.json')), sys, _usage);
    final code = await runLocked(
      job: 'finish:$slug',
      config: config,
      status: status,
      ownerPid: ownerPid,
      body: (stage) async {
        if (sessions.isEmpty) throw StateError('no analysed session of $slug');
        final stamps = [for (final s in sessions) s.stamp];
        var state = _read();
        if (state['state'] == 'done' &&
            jsonEncode(state['sessions']) == jsonEncode(stamps)) {
          status.write(1, 1, 1, StageState.done);
          return;
        }
        // New sessions since the last finish: merge again, keep the spend.
        if (state['state'] == 'done') {
          state = {
            'tokens': state['tokens'],
            'cost_usd': state['cost_usd'],
            'sessions': stamps,
          };
        }
        status.write(1, 0, 1, StageState.running);
        await RecordingFlag(
          config.dataDir,
          procRoot: config.procRoot,
        ).waitClear(recordingPoll);
        final last = sessions.last;
        state['sessions'] = stamps;
        if (state['merged'] == null) await _merge(state, sessions, last);
        state['todo'] ??= await _todo(last);
        state['state'] = 'done';
        state['finished_unix'] = sys.nowUnix();
        _write(state);
        status.write(1, 1, 1, StageState.done);
      },
    );
    return code;
  }

  Future<void> _merge(
    Map<String, Object?> state,
    List<FinishSession> sessions,
    FinishSession last,
  ) async {
    final template = templatePath(last.target);
    if (!File(template).existsSync()) {
      throw StateError('no questions template in ${last.target}');
    }
    final prompt = buildFinishPrompt(
      game: last.game,
      template: template,
      drafts: [for (final s in sessions) (stamp: s.stamp, path: s.draft)],
      markers: [
        for (final s in sessions)
          (stamp: s.stamp, path: p.join(s.dir, 'markers.jsonl')),
      ],
    );
    final promptFile = File(p.join(_dir, 'finish_prompt.txt'))
      ..writeAsStringSync(prompt);
    final answer = await _ask(prompt, promptFile.path, [
      last.target,
      for (final s in sessions) s.dir,
    ]);
    final spent = _usage() + answer.usage;
    state
      ..['state'] = 'running'
      ..['tokens'] = spent.tokens
      ..['cost_usd'] = spent.costUsd;
    _write(state);
    final error = answer.error;
    if (error != null) {
      if (isRateLimited(error)) throw WaitingError('finish: $error');
      throw StateError('finish failed: $error');
    }
    final docs = parseFinish(
      answer.text,
      template: File(template).readAsStringSync(),
    );
    final merged = mergedPath(last.target, slug);
    final report = reportPath(last.target, slug);
    File(merged)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(docs.merged);
    File(report).writeAsStringSync(docs.report);
    state
      ..['merged'] = merged
      ..['report'] = report
      ..['model'] = answer.model;
    _write(state);
  }

  Future<String> _todo(FinishSession last) async {
    final remote = await sys.run('git', [
      '-C',
      last.target,
      'remote',
      'get-url',
      'origin',
    ]);
    final repo = repoSlugFromRemote(
      remote.exitCode == 0 ? '${remote.stdout}' : null,
      p.basename(last.target),
    );
    final cmd = config.todoCmd;
    final text =
        '${finishTodoTitle(last.game)}\n\nReport (uncommitted):\n'
        '- ${reportPath(last.target, slug)}\n'
        '- ${mergedPath(last.target, slug)}';
    final r = await sys.run(cmd.first, [
      ...cmd.skip(1),
      '--repo',
      repo,
      '--new-note',
      '--by',
      'claude',
      '--done-check',
      finishDoneCheck(slug),
      '--text',
      text,
    ], workingDirectory: p.join(config.home, 'src', 'todo'));
    if (r.exitCode != 0) {
      throw StateError('todo task failed (${r.exitCode}): ${r.stderr}');
    }
    return '${r.stdout}'.trim();
  }
}
