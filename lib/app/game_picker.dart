/// Installed games as capsule images, no text. A game without a cached
/// capsule gets a procedural tile: a hue from its app id and a pad glyph.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/models.dart';

/// The capsule grid.
class GamePicker extends StatelessWidget {
  /// Creates the grid.
  const new({
    required this.games,
    required this.selected,
    required this.onPick,
    required this.capsuleUrl,
    this.enabled = true,
    super.key,
  });

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
    if (games.isEmpty) {
      return const Center(
        child: Icon(
          Icons.videogame_asset_off_rounded,
          size: 96,
          color: AppPalette.mutedOnDark,
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
  });

  final Game game;
  final bool picked;
  final bool enabled;
  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final art = game.capsule
        ? Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ProceduralCapsule(appid: game.appid),
          )
        : ProceduralCapsule(appid: game.appid);
    return Semantics(
      button: true,
      selected: picked,
      label: game.name,
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
  }
}

/// A capsule drawn from the app id: a hue band and a gamepad glyph.
class ProceduralCapsule extends StatelessWidget {
  /// Creates the tile.
  const new({required this.appid, super.key});

  /// App id seeding the hue.
  final int appid;

  @override
  Widget build(BuildContext context) {
    final hue = (appid * 47) % 360;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            HSLColor.fromAHSL(1, hue.toDouble(), 0.35, 0.32).toColor(),
            AppPalette.inkRaised1,
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.sports_esports_rounded,
          size: 72,
          color: AppPalette.textOnDark,
        ),
      ),
    );
  }
}
