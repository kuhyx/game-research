/// A control's global hotkey as a key legend (`Super+Shift+F4`) under it.
///
/// kuhy, 2026-11-11: "put them as text I allow it in this case". The legend
/// comes from `kHotkeys`, the table the session's sxhkd config is generated
/// from, so the label cannot drift from the real binding.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/core/hotkeys.dart';

/// The hotkey of [action] (a marker tag or `stop`); an empty line of the
/// same height when [action] is null or unbound, so rows do not jump.
class ShortcutLabel extends StatelessWidget {
  /// Creates the label; [active] while the hotkeys are live (recording).
  const new(this.action, {required this.active, super.key});

  /// Marker tag or `stop`.
  final String? action;

  /// Whether the key works now (sxhkd runs only while recording).
  final bool active;

  @override
  Widget build(BuildContext context) {
    final keys = action == null ? null : shortcutFor(action!);
    // The button's semantics hint carries the same keys.
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          keys ?? '',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: active ? AppPalette.textOnDark : AppPalette.mutedOnDark,
          ),
        ),
      ),
    );
  }
}
