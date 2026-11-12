/// Ignores row-action taps for a short while after the screen changed under
/// the pointer.
///
/// 2026-11-12: `open-draft` fired on its own, once 2.6 s after a game ended
/// and once 1.2 s after Steam was launched. Both are moments when a game or
/// Steam window closes or opens over this one; a click meant for that
/// window (a double click on the game's Quit, a click on a Steam dialog)
/// lands on the session row that sits under the pointer. Rerun costs model
/// tokens and draft opens a panel, so neither may fire from such a click.
library;

import 'dart:async';

/// A resettable quiet period.
class TapGuard {
  Timer? _timer;

  /// Whether taps are being ignored.
  bool get quiet => _timer?.isActive ?? false;

  /// Ignores taps for [duration] from now (extends a running period).
  void hush([Duration duration = const Duration(seconds: 5)]) {
    _timer?.cancel();
    _timer = Timer(duration, () {});
  }

  /// Runs [action] unless quiet; returns whether it ran.
  bool run(void Function() action) {
    if (quiet) return false;
    action();
    return true;
  }

  /// Stops the timer.
  void dispose() => _timer?.cancel();
}
