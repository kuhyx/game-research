/// The tile of a game with no art: a hue from the app id and a pad glyph.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

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
