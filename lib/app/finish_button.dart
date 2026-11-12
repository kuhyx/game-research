/// The per-game "research finished" control on a game tile: a flag that
/// starts the merge of the game's drafts, shows its progress as a ring, and
/// opens the report once it exists. Icons only.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/models.dart';

/// The round control for [game].
class FinishButton extends StatelessWidget {
  /// Creates the control; [ready]: some session of the game has a draft.
  const new({
    required this.game,
    required this.ready,
    required this.onPressed,
    super.key,
  });

  /// The game.
  final Game game;

  /// Whether there is anything to merge yet.
  final bool ready;

  /// Pressed.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final job = game.finish?.job;
    final state = job?.state ?? 'idle';
    final (icon, color) = switch (state) {
      'running' => (Icons.flag_rounded, AppPalette.accent),
      'waiting' => (Icons.hourglass_top_rounded, AppPalette.warning),
      'interrupted' => (Icons.pause_rounded, AppPalette.warning),
      'failed' => (Icons.priority_high_rounded, AppPalette.danger),
      'done' => (Icons.task_alt_rounded, AppPalette.success),
      _ => (
        Icons.flag_outlined,
        ready ? AppPalette.textOnDark : AppPalette.mutedOnDark,
      ),
    };
    final semanticLabel = 'finished ${game.appid}';
    return Semantics(
      button: true,
      label: semanticLabel,
      value: state,
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        color: AppPalette.ink.withValues(alpha: 0.85),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (job != null && (job.active || state == 'interrupted'))
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      value: job.progress,
                      strokeWidth: 4,
                      color: color,
                      backgroundColor: AppPalette.lineDark,
                    ),
                  ),
                Icon(icon, color: color, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
