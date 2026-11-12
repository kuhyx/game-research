/// Stage 3: ONE Opus call per session fills the target's questions template;
/// the draft is written uncommitted into the target (one file per session,
/// never overwriting an earlier one) and one todo task asks kuhy to review
/// it. `stage3.json` records each finished step and the tokens spent, so a
/// rerun after a failed todo call does not pay for a second Opus call.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/analysis/job.dart';
import 'package:game_research/analysis/tiers.dart';
import 'package:game_research/core/captions.dart';
import 'package:game_research/core/sampling.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:game_research/core/usage.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// Runs stage 3 on session folder [dir].
class Stage3 {
  /// Creates the stage.
  const new(this.dir, this.config, this.sys);

  /// Session folder.
  final String dir;

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  File get _state => File(p.join(dir, 'analysis', 'stage3.json'));

  Map<String, Object?> _read() => _state.existsSync()
      ? jsonDecode(_state.readAsStringSync()) as Map<String, Object?>
      : <String, Object?>{};

  void _write(Map<String, Object?> s) =>
      _state.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(s));

  /// Adds [spent] to the `tokens` and `cost_usd` of [state]: a call that
  /// failed or answered badly cost tokens too.
  void _spend(Map<String, Object?> state, Usage spent) {
    final total =
        Usage.fromJson({
          ...?(state['tokens'] as Map?)?.cast<String, Object?>(),
          'cost_usd': state['cost_usd'],
        }) +
        spent;
    state
      ..['tokens'] = total.tokens
      ..['cost_usd'] = total.costUsd;
    _write(state);
  }

  /// The synthesis model call: Opus, or the fake.
  Future<TierResult> _synthesize(
    String prompt,
    String promptFile,
    String target,
  ) {
    if (config.fakeLlm.isNotEmpty) {
      return FakeTier(config, sys, 'opus').call(promptFile);
    }
    return ClaudeTier(
      config,
      sys,
      model: 'opus',
      limitS: 1500,
    ).ask(prompt, [dir, target]);
  }

  /// Fills the draft for [meta] (session.json) from [frames].
  Future<Map<String, Object?>> run(
    Map<String, Object?> meta,
    List<SampleFrame> frames,
  ) async {
    final state = _read();
    final game = meta['game']! as String;
    final slug = meta['slug']! as String;
    final target = meta['target']! as String;
    final stamp = sessionStamp(p.basename(dir));
    final template = templatePath(target);
    if (!File(template).existsSync()) {
      throw StateError('no questions template in $target/docs/research');
    }
    final draft = draftPath(target, slug, stamp);
    if (state['draft'] == null) {
      final duration = (meta['duration_s'] as num?)?.toDouble() ?? 0;
      final picked = pickSynthesisFrames(frames, synthesisFrameCap(duration));
      final a = p.join(dir, 'analysis');
      final prompt = buildSynthesisPrompt(
        game: game,
        session: p.basename(dir),
        template: template,
        earlier: priorDrafts(target, slug, exceptStamp: stamp),
        captions: p.join(a, 'captions.jsonl'),
        markers: p.join(dir, 'markers.jsonl'),
        stills: p.join(a, 'still.jsonl'),
        frames: [for (final f in picked) p.join(a, 'frames', f.file)],
      );
      final promptFile = File(p.join(a, 'synthesis_prompt.txt'))
        ..writeAsStringSync(prompt);
      final answer = await _synthesize(prompt, promptFile.path, target);
      _spend(state, answer.usage);
      final error = answer.error;
      if (error != null) {
        if (isRateLimited(error)) throw WaitingError('synthesis: $error');
        throw StateError('synthesis failed: $error');
      }
      final doc = parseDoc(
        answer.text,
        template: File(template).readAsStringSync(),
      );
      File(draft)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(doc);
      state
        ..['draft'] = draft
        ..['model'] = answer.model
        ..['frames'] = picked.length;
      _write(state);
    }
    if (state['todo'] == null) {
      state['todo'] = await _todo(game, slug, target, stamp);
      _write(state);
    }
    return state;
  }

  Future<String> _todo(
    String game,
    String slug,
    String target,
    String stamp,
  ) async {
    final remote = await sys.run('git', [
      '-C',
      target,
      'remote',
      'get-url',
      'origin',
    ]);
    final repo = repoSlugFromRemote(
      remote.exitCode == 0 ? '${remote.stdout}' : null,
      p.basename(target),
    );
    final cmd = config.todoCmd;
    final text =
        '${todoTaskTitle(game)}\n\nDraft (uncommitted):\n'
        '- ${draftPath(target, slug, stamp)}\n\nSession: $dir';
    final r = await sys.run(cmd.first, [
      ...cmd.skip(1),
      '--repo',
      repo,
      '--new-note',
      '--by',
      'claude',
      '--done-check',
      todoDoneCheck(slug, stamp),
      '--text',
      text,
    ], workingDirectory: p.join(config.home, 'src', 'todo'));
    if (r.exitCode != 0) {
      throw StateError('todo task failed (${r.exitCode}): ${r.stderr}');
    }
    return '${r.stdout}'.trim();
  }
}
