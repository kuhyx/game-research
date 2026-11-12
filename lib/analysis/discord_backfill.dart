/// `game_research_analyze --discord-backfill`: writes the Discord version of
/// every session draft and game report that has none (the docs written before
/// this existed, and the ones whose short version failed or went stale).
///
/// Runs under the machine-wide job lock like any job, waits while a recording
/// runs, and skips every document whose `X.discord.md` exists. A usage limit
/// ends the run as waiting (exit 4, run it again later); any other failure is
/// reported per document and the run goes on (exit 1 at the end).
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/analysis/discord_doc.dart';
import 'package:game_research/analysis/job.dart';
import 'package:game_research/core/discord_doc.dart';
import 'package:game_research/core/safe_json.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/core/usage.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/recording_flag.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// The job id the lock uses.
const kBackfillJob = 'discord-backfill';

/// One document without a short version, and where its outcome is noted.
class _Todo {
  const new(this.doc, this.workDir, this.stateFile, this.key);

  /// The research document.
  final String doc;

  /// Where the prompt files go.
  final String workDir;

  /// The job state file (`stage3.json` or `finish.json`).
  final File stateFile;

  /// The key in it (`discord` or `report_discord`).
  final String key;
}

/// The backfill job.
class DiscordBackfill {
  /// Creates the job; failures go to [err].
  new(
    this.config,
    this.sys, {
    required this.err,
    this.recordingPoll = const Duration(seconds: 5),
  });

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  /// Where per-document failures are reported.
  final IOSink err;

  /// How often a recording is checked again.
  final Duration recordingPoll;

  Usage _spent = Usage.zero;

  /// Every draft and report named by a job state, in session order, without
  /// a short version. A v1 draft shared by sessions counts once.
  List<_Todo> _missing() {
    final out = <_Todo>[];
    final seen = <String>{};
    void add(String? doc, String workDir, File state, String key) {
      if (doc == null || !seen.add(doc) || !File(doc).existsSync()) return;
      if (!File(discordPathOf(doc)).existsSync()) {
        out.add(_Todo(doc, workDir, state, key));
      }
    }

    final root = Directory(config.dataDir);
    if (!root.existsSync()) return out;
    final dirs = root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final d in dirs) {
      final state = File(p.join(d.path, 'analysis', 'stage3.json'));
      final draft =
          readJsonObject(state)?['draft'] ?? readJsonObject(state)?['draft_en'];
      add(
        draft is String ? draft : null,
        p.join(d.path, 'analysis'),
        state,
        'discord',
      );
    }
    final games = Directory(p.join(config.dataDir, 'games'));
    if (!games.existsSync()) return out;
    final slugs = games.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final g in slugs) {
      final state = File(p.join(g.path, 'finish.json'));
      final report = readJsonObject(state)?['report'];
      add(report is String ? report : null, g.path, state, 'report_discord');
    }
    return out;
  }

  void _note(_Todo t, String outcome) {
    final state = readJsonObject(t.stateFile) ?? <String, Object?>{};
    state[t.key] = outcome;
    writeAtomic(t.stateFile, const JsonEncoder.withIndent(' ').convert(state));
  }

  /// Runs the job. Returns the exit code ([JobExit]).
  Future<int> run() async {
    final status = StatusWriter(
      File(p.join(config.dataDir, 'discord_backfill.json')),
      sys,
      () => _spent,
    );
    final flag = RecordingFlag(config.dataDir, procRoot: config.procRoot);
    var failed = 0;
    final code = await runLocked(
      job: kBackfillJob,
      config: config,
      status: status,
      body: (stage) async {
        final todo = _missing();
        for (var i = 0; i < todo.length; i++) {
          await flag.waitClear(recordingPoll);
          status.write(1, i, todo.length, StageState.running);
          final t = todo[i];
          try {
            await writeDiscord(
              t.doc,
              (prompt, file) => askOpus(
                config: config,
                sys: sys,
                prompt: prompt,
                promptFile: file,
                dirs: [t.workDir, p.dirname(t.doc)],
                spent: (u) => _spent += u,
              ),
              t.workDir,
            );
            _note(t, kDiscordOk);
          } on WaitingError {
            rethrow;
          } on Object catch (e) {
            failed++;
            err.writeln('discord: ${t.doc}: ${discordFailure(e)}');
            _note(t, discordFailure(e));
          }
        }
        status.write(1, todo.length, todo.length, StageState.done);
      },
    );
    return code == JobExit.done && failed > 0 ? JobExit.failed : code;
  }
}
