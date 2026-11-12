/// Numbers with an icon in front: the token total, cost, stage, items done,
/// minutes left and average fps of a job or session. No words, no unit
/// letters; what a number means is its icon and its semantics label.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/job_models.dart';

/// The chips of [job]; [fpsAvg] adds the session's average frame rate.
class StatChips extends StatelessWidget {
  /// Creates the chips.
  const new({required this.job, this.fpsAvg, super.key});

  /// The analysis or finish job.
  final JobStatus job;

  /// Average fps of the session, when logged.
  final double? fpsAvg;

  @override
  Widget build(BuildContext context) {
    final tokens = job.tokens?.total ?? 0;
    final cost = job.costUsd ?? 0;
    final eta = job.etaMin;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        if (tokens > 0) _Chip(Icons.toll_rounded, grouped(tokens), 'tokens'),
        if (cost > 0)
          _Chip(Icons.attach_money_rounded, cost.toStringAsFixed(2), 'cost'),
        if (job.active && job.stage > 0)
          _Chip(Icons.layers_rounded, '${job.stage}', 'stage'),
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

class _Chip extends StatelessWidget {
  const new(this.icon, this.value, this.semanticLabel);

  final IconData icon;
  final String value;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      value: value,
      excludeSemantics: true,
      child: Row(
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
    );
  }
}
