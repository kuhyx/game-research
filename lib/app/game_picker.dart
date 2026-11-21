/// Library games as capsule images, no text. A game without a cached
/// capsule gets a procedural tile: a hue from its app id and a pad glyph.
/// Games the enforcer blocks are dimmed under a [LockBadge]; tapping one
/// asks (icons only) to add it as the research game.
library;

import 'package:design_system/design_system.dart';
import 'package:game_research/app/finish_button.dart';
import 'package:game_research/app/install_bar.dart';
import 'package:game_research/app/lock_badge.dart';
import 'package:game_research/app/models.dart';
import 'package:game_research/app/panel_host.dart';
import 'package:game_research/app/procedural_capsule.dart';
import 'package:game_research/app/stat_chips.dart';
import 'package:material_ui/material_ui.dart';

export 'package:game_research/app/procedural_capsule.dart';

/// The capsule grid.
class GamePicker extends StatelessWidget {
  /// Creates the grid.
  const new({
    required this.games,
    required this.selected,
    required this.onPick,
    required this.capsuleUrl,
    this.enabled = true,
    this.finishReady = const {},
    this.actions,
    this.offline = false,
    super.key,
  });

  /// The wrapper does not answer: a cloud glyph instead of the grid.
  final bool offline;

  /// App ids with at least one session draft (the finish control works).
  final Set<int> finishReady;

  /// Finish and research game actions (null: no finish control, no adds).
  final PanelActions? actions;

  /// Games to show.
  final List<Game> games;

  /// The picked app id.
  final int? selected;

  /// Called with the tapped app id.
  final ValueChanged<int> onPick;

  /// Capsule image URL of an app id.
  final String Function(int appid) capsuleUrl;

  /// False while recording: the pick is locked.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (offline) {
      return const Center(
        child: Icon(
          Icons.cloud_off_rounded,
          size: 96,
          color: AppPalette.danger,
          semanticLabel: 'wrapper offline',
        ),
      );
    }
    if (games.isEmpty) {
      return const Center(
        child: Icon(
          Icons.videogame_asset_off_rounded,
          size: 96,
          color: AppPalette.danger,
          semanticLabel: 'no games',
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 2 / 3,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
      ),
      itemCount: games.length,
      itemBuilder: (context, i) => _Capsule(
        game: games[i],
        picked: games[i].appid == selected,
        enabled: enabled,
        url: capsuleUrl(games[i].appid),
        onTap: () => onPick(games[i].appid),
        finishReady: finishReady.contains(games[i].appid),
        actions: actions,
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const new({
    required this.game,
    required this.picked,
    required this.enabled,
    required this.url,
    required this.onTap,
    required this.finishReady,
    required this.actions,
  });

  final Game game;
  final bool picked;
  final bool enabled;
  final String url;
  final VoidCallback onTap;
  final bool finishReady;
  final PanelActions? actions;

  @override
  Widget build(BuildContext context) {
    final onFinish = actions == null || !game.installed
        ? null
        : () => actions!.finish(game);
    final tap = enabled ? tileTap(context, game, actions, onPick: onTap) : null;
    final dim = game.lock == TileLock.blocked || game.lock == TileLock.taken;
    final semanticLabel = [
      game.name,
      if (game.updating) 'updating',
      if (game.lock != TileLock.open) game.lock.name,
    ].join(', ');
    final art = game.capsule
        ? Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ProceduralCapsule(appid: game.appid),
          )
        : ProceduralCapsule(appid: game.appid);
    final tile = Semantics(
      button: true,
      selected: picked,
      label: semanticLabel,
      onTap: tap,
      excludeSemantics: true,
      child: Opacity(
        opacity: (enabled || picked) && !dim ? 1 : 0.45,
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AnimatedContainer(
            duration: AppDuration.fast,
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: picked ? AppPalette.accent : Colors.transparent,
                width: 4,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  art,
                  if (game.updating) InstallBar(progress: game.progress),
                  if (!game.installed && game.lock == TileLock.research)
                    const InstallBar(progress: null),
                  if (picked)
                    const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: AppPalette.accent,
                          size: 36,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // Beside the tile's semantics, not inside it: that node hides its
    // children from assistive tech.
    final badge = Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: LockBadge(
          lock: game.lock,
          onRemove: () => removeResearch(context, actions),
        ),
      ),
    );
    if (onFinish == null) {
      return Stack(
        children: [
          Positioned.fill(child: tile),
          badge,
        ],
      );
    }
    final job = game.finish?.job;
    return Stack(
      children: [
        Positioned.fill(child: tile),
        badge,
        Positioned(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: AppSpacing.md,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: job == null
                    ? const SizedBox.shrink()
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppPalette.ink.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          child: StatChips(job: job),
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.xs),
              FinishButton(game: game, ready: finishReady, onPressed: onFinish),
            ],
          ),
        ),
      ],
    );
  }
}
