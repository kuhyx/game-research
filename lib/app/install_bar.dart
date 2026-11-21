/// The download glyph and bar over a capsule tile.
library;

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// Steam stopped this game mid-download: a download glyph and how far it
/// got (null: the install was asked for, nothing downloaded yet). Starting
/// it still works; Steam finishes the download first.
class InstallBar extends StatelessWidget {
  /// Creates the bar.
  const new({required this.progress, super.key});

  /// Downloaded share, 0..1; null: not started.
  final double? progress;

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
