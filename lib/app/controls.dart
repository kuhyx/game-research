/// Start/Stop, the elapsed clock, the four marker buttons and the one-line
/// note field. Icons and numbers only; every control has a semantics label.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_research/app/marker_style.dart';
import 'package:game_research/app/models.dart';

/// The session controls.
class Controls extends StatelessWidget {
  /// Creates the controls.
  const new({
    required this.state,
    required this.canStart,
    required this.elapsedS,
    required this.onStart,
    required this.onStop,
    required this.onMarker,
    required this.noteOpen,
    required this.onNote,
    super.key,
  });

  /// The wrapper's state.
  final AppState state;

  /// Whether a game is picked and nothing records.
  final bool canStart;

  /// Seconds since the session started.
  final double elapsedS;

  /// Start pressed.
  final VoidCallback onStart;

  /// Stop pressed.
  final VoidCallback onStop;

  /// A marker button pressed, with its tag.
  final ValueChanged<String> onMarker;

  /// Whether the note field is open.
  final bool noteOpen;

  /// The note text submitted ('' = closed without text).
  final ValueChanged<String> onNote;

  @override
  Widget build(BuildContext context) {
    final rec = state.recording;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _StartStop(
                  recording: rec,
                  enabled: rec || canStart,
                  error: state.error,
                  onPressed: rec ? onStop : onStart,
                ),
                const SizedBox(width: AppSpacing.lg),
                Icon(
                  Icons.fiber_manual_record_rounded,
                  color: rec ? AppPalette.danger : AppPalette.lineDark,
                  size: 32,
                  semanticLabel: rec ? 'recording' : 'idle',
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    clock(rec ? elapsedS : 0),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: rec
                          ? AppPalette.textOnDark
                          : AppPalette.mutedOnDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                for (final s in kMarkerStyles)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: _MarkerButton(
                        style: s,
                        count: state.counts[s.tag] ?? 0,
                        enabled: rec,
                        onPressed: () => onMarker(s.tag),
                      ),
                    ),
                  ),
              ],
            ),
            if (noteOpen) _NoteField(onNote: onNote),
          ],
        ),
      ),
    );
  }
}

class _StartStop extends StatelessWidget {
  const new({
    required this.recording,
    required this.enabled,
    required this.error,
    required this.onPressed,
  });

  final bool recording;
  final bool enabled;
  final String error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final failed = error.isNotEmpty && !recording;
    final semanticLabel = recording ? 'stop' : 'start';
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      value: failed ? error : null,
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: SizedBox(
        width: 96,
        height: 96,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: recording || failed
                ? AppPalette.danger
                : AppPalette.accent,
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
          ),
          child: Icon(
            recording
                ? Icons.stop_rounded
                : (failed ? Icons.error_rounded : Icons.play_arrow_rounded),
            size: 56,
          ),
        ),
      ),
    );
  }
}

class _MarkerButton extends StatelessWidget {
  const new({
    required this.style,
    required this.count,
    required this.enabled,
    required this.onPressed,
  });

  final MarkerStyle style;
  final int count;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = 'marker ${style.tag}';
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      value: '$count',
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: style.color,
          side: BorderSide(
            color: enabled ? style.color : AppPalette.lineDark,
            width: 2,
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(style.icon, size: 40),
            const SizedBox(width: AppSpacing.sm),
            Text('$count', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _NoteField extends StatelessWidget {
  const new({required this.onNote});

  final ValueChanged<String> onNote;

  @override
  Widget build(BuildContext context) {
    const semanticLabel = 'note text';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => onNote(''),
        },
        child: Semantics(
          label: semanticLabel,
          child: TextField(
            autofocus: true,
            onSubmitted: onNote,
            decoration: const InputDecoration(
              prefixIcon: Icon(
                Icons.edit_note_rounded,
                color: Color(0xFF2F6FE2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
