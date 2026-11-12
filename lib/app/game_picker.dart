/// Installed games as capsule images, no text. A game without a cached
/// capsule gets a procedural tile: a hue from its app id and a pad glyph.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/finish_button.dart';
import 'package:game_research/app/models.dart';
import 'package:game_research/app/procedural_capsule.dart';
import 'package:game_research/app/stat_chips.dart';

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
    this.onFinish,
    this.offline = false,
    super.key,
  });

  /// The wrapper does not answer: a cloud glyph instead of the grid.
  final bool offline;

  /// App ids with at least one session draft (the finish control works).
  final Set<int> finishReady;

  /// The finish control of a game was pressed.
  final ValueChanged<Game>? onFinish;

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
        onFinish: onFinish == null ? null : () => onFinish!(games[i]),
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
    required this.onFinish,
  });

  final Game game;
  final bool picked;
  final bool enabled;
  final String url;
  final VoidCallback onTap;
  final bool finishReady;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
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
      label: game.updating ? '${game.name}, updating' : game.name,
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled || picked ? 1 : 0.35,
        child: InkWell(
          onTap: enabled ? onTap : null,
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
                  if (game.updating) _Updating(progress: game.progress),
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
    if (onFinish == null) return tile;
    final job = game.finish?.job;
    // Beside the tile's semantics, not inside it: that node hides its
    // children from assistive tech.
    return Stack(
      children: [
        Positioned.fill(child: tile),
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
              FinishButton(
                game: game,
                ready: finishReady,
                onPressed: onFinish!,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Steam stopped this game mid-download: a download glyph and how far it
/// got. Starting it still works; Steam finishes the download first.
class _Updating extends StatelessWidget {
  const new({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: Icon(
          Icons.downloading_rounded,
          color: AppPalette.textOnDark,
          size: 36,
        ),
      ),
      const Spacer(),
      LinearProgressIndicator(
        value: progress,
        minHeight: 8,
        color: AppPalette.accent,
      ),
    ],
  );
}
