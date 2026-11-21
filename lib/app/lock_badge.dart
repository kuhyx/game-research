/// The enforcer's mark on a picker tile (textgate: icons only) and the
/// icon-only confirm dialog of the research game.
///
/// Lock: blocked by steam-backlog-enforcer; tapping offers the flask (add
/// as research game). Lock plus "no entry": blocked, and the one research
/// slot is taken. Flask: the research game, with a minus to remove it.
library;

import 'package:design_system/design_system.dart';
import 'package:game_research/app/models.dart';
import 'package:game_research/app/panel_host.dart';
import 'package:material_ui/material_ui.dart';

/// The mark of one tile.
class LockBadge extends StatelessWidget {
  /// Creates the mark of [lock]; [onRemove] removes the research game.
  const new({required this.lock, this.onRemove, super.key});

  /// What the enforcer does with the game.
  final TileLock lock;

  /// The minus of the research game was pressed.
  final VoidCallback? onRemove;

  static Widget _chip(List<Widget> icons) => Padding(
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.ink.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(mainAxisSize: MainAxisSize.min, children: icons),
      ),
    ),
  );

  static const _lock = Icon(
    Icons.lock_rounded,
    color: AppPalette.textOnDark,
    size: 36,
    semanticLabel: 'blocked',
  );

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: switch (lock) {
      TileLock.open => const SizedBox.shrink(),
      TileLock.blocked => _chip(const [_lock]),
      TileLock.taken => _chip(const [
        _lock,
        Icon(
          Icons.do_not_disturb_on_rounded,
          color: AppPalette.danger,
          size: 36,
          semanticLabel: 'slot taken',
        ),
      ]),
      TileLock.research => _chip([
        const Icon(
          Icons.science_rounded,
          color: AppPalette.accent,
          size: 36,
          semanticLabel: 'research game',
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(
            Icons.remove_circle_rounded,
            color: AppPalette.textOnDark,
            size: 32,
            semanticLabel: 'remove research game',
          ),
        ),
      ]),
    },
  );
}

/// Asks yes/no with [icon] alone; true on the tick.
Future<bool> confirmIcon(BuildContext context, IconData icon) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Icon(icon, size: 96, color: AppPalette.accent),
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close_rounded, semanticLabel: 'cancel'),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check_rounded, semanticLabel: 'confirm'),
          ),
        ],
      ),
    ) ??
    false;

/// What a tap on [game] does: pick an installed game ([onPick]), add a
/// blocked one after the icon dialog, retry the research game's install.
VoidCallback? tileTap(
  BuildContext context,
  Game game,
  PanelActions? actions, {
  required VoidCallback onPick,
}) {
  final add = actions?.research;
  return switch (game.lock) {
    TileLock.taken => null,
    TileLock.blocked when add != null => () async {
      if (await confirmIcon(context, Icons.science_rounded)) add(game.appid);
    },
    TileLock.research when !game.installed && add != null => () => add(
      game.appid,
    ),
    _ => game.installed ? onPick : null,
  };
}

/// The research game's minus: asks, then removes it.
Future<void> removeResearch(BuildContext context, PanelActions? actions) async {
  final remove = actions?.unresearch;
  if (remove == null) return;
  if (await confirmIcon(context, Icons.remove_circle_rounded)) remove();
}
