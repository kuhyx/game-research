/// The phases of a session flow (`SessionFlow.phase`).
library;

/// Where the flow is.
enum Phase {
  /// Nothing pending, nothing recording.
  idle,

  /// The autostart ring is draining.
  armed,

  /// The Steam command runs.
  launching,

  /// Waiting for the game window.
  waiting,

  /// A session records.
  recording,
}
