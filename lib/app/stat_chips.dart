/// Numbers with an icon in front: the token total (coin), cost, items done,
/// minutes left and average fps of a job or session, and on a session row
/// the three stages as icons. A session row puts one word under each stat
/// (`kStatWords`, kuhy's exception); a game tile shows the numbers only.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/job_models.dart';
import 'package:game_research/app/stat_words.dart';

/// The stages in order: video = scan, eye = captions, page = draft.
const List<(String, IconData)> _stages = [
  ('scan', Icons.videocam_rounded),
  ('captions', Icons.visibility_rounded),
  ('draft', Icons.description_outlined),
];

/// The chips of [job]; [fpsAvg] adds the session's average frame rate.
class StatChips extends StatelessWidget {
  /// Creates the chips; [words] adds the word under each stat and the stage
  /// icons (session rows).
  const new({required this.job, this.fpsAvg, this.words = false, super.key});

  /// The analysis or finish job.
  final JobStatus job;

  /// Average fps of the session, when logged.
  final double? fpsAvg;

  /// Whether this is a session row: stage icons and a word under each stat.
  final bool words;

  String? _word(String key) => words ? kStatWords[key] : null;

  @override
  Widget build(BuildContext context) {
    final tokens = job.tokens?.total ?? 0;
    final cost = job.costUsd ?? 0;
    final eta = job.etaMin;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        if (tokens > 0)
          _Chip(
            Icons.toll_rounded,
            compactTokens(tokens),
            'tokens',
            _word('tokens'),
          ),
        if (cost > 0)
          _Chip(
            Icons.attach_money_rounded,
            cost.toStringAsFixed(2),
            'cost',
            _word('cost'),
          ),
        if (words) _StageIcons(job),
        if (job.active && job.showsItems)
          _Chip(Icons.checklist_rounded, '${job.done}/${job.total}', 'items'),
        if (job.active && eta != null)
          _Chip(Icons.timer_outlined, '$eta', 'minutes left'),
        if (fpsAvg != null)
          _Chip(Icons.speed_rounded, '${fpsAvg!.round()}', 'fps'),
      ],
    );
  }
}

/// Three small icons: finished stages green with a check, the current one
/// lit (accent, red when failed), later ones grey.
class _StageIcons extends StatelessWidget {
  const new(this.job);

  final JobStatus job;

  @override
  Widget build(BuildContext context) {
    final current = job.state == 'done' ? 4 : job.stage;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _stages.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : AppSpacing.sm),
            child: _Stage(
              key: ValueKey(_stages[i].$1),
              word: _stages[i].$1,
              icon: _stages[i].$2,
              finished: i + 1 < current,
              lit: i + 1 == current,
              failed: job.state == 'failed',
            ),
          ),
      ],
    );
  }
}

class _Stage extends StatelessWidget {
  const new({
    required this.word,
    required this.icon,
    required this.finished,
    required this.lit,
    required this.failed,
    super.key,
  });

  final String word;
  final IconData icon;
  final bool finished;
  final bool lit;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final color = finished
        ? AppPalette.success
        : lit
        ? (failed ? AppPalette.danger : AppPalette.accent)
        : AppPalette.mutedOnDark;
    final state = finished ? 'done' : (lit ? 'current' : 'later');
    return Semantics(
      label: word,
      value: state,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 20, color: color),
              if (finished)
                const Positioned(
                  right: -5,
                  bottom: -3,
                  child: Icon(
                    Icons.done_rounded,
                    size: 12,
                    color: AppPalette.success,
                  ),
                ),
            ],
          ),
          _Word(kStatWords[word]!, color),
        ],
      ),
    );
  }
}

class _Word extends StatelessWidget {
  const new(this.word, this.color);

  final String word;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    word,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
  );
}

class _Chip extends StatelessWidget {
  const new(this.icon, this.value, this.semanticLabel, [this.word]);

  final IconData icon;
  final String value;
  final String semanticLabel;
  final String? word;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      value: value,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppPalette.mutedOnDark),
              const SizedBox(width: AppSpacing.xs),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppPalette.mutedOnDark,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (word != null) _Word(word!, AppPalette.mutedOnDark),
        ],
      ),
    );
  }
}
