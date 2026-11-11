/// The ring around the start/stop button: drains over the autostart
/// countdown (Esc or the button cancels), spins while Steam brings the game
/// up. No text: the ring is the countdown.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/models.dart';

/// Wraps [child] (the 96 px button) in the phase ring.
class StartRing extends StatelessWidget {
  /// Creates the ring for [state]; [now] is unix seconds.
  const new({
    required this.state,
    required this.now,
    required this.child,
    super.key,
  });

  /// The wrapper's state.
  final AppState state;

  /// Wall clock.
  final double Function() now;

  /// The button.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final deadline = state.deadlineUnix;
    final Widget ring;
    if (state.phase == 'armed' && deadline != null && state.totalS > 0) {
      final left = (deadline - now()).clamp(0, state.totalS).toDouble();
      const semanticLabel = 'autostart';
      ring = Semantics(
        label: semanticLabel,
        value: '${left.ceil()}',
        child: TweenAnimationBuilder<double>(
          key: ValueKey(deadline),
          tween: Tween(begin: left / state.totalS, end: 0),
          duration: Duration(milliseconds: (left * 1000).round()),
          builder: (_, v, _) => CircularProgressIndicator(
            value: v,
            strokeWidth: 8,
            color: AppPalette.accent,
          ),
        ),
      );
    } else if (state.phase == 'launching' || state.phase == 'waiting') {
      const semanticLabel = 'waiting for game';
      ring = Semantics(
        label: semanticLabel,
        child: const CircularProgressIndicator(
          strokeWidth: 8,
          color: AppPalette.accent,
        ),
      );
    } else {
      return child;
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(width: 116, height: 116, child: ring),
        child,
      ],
    );
  }
}
