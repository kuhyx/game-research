/// The target project: one folder chip per candidate repo. The repo's folder
/// name is data (kuhy's own repo names), not UI copy.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// The chips.
class TargetPicker extends StatelessWidget {
  /// Creates the picker.
  const new({
    required this.paths,
    required this.current,
    required this.onPick,
    super.key,
  });

  /// Candidate target folders.
  final List<String> paths;

  /// The picked one.
  final String current;

  /// Called with the tapped path.
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      for (final path in paths)
        ChoiceChip(
          avatar: const Icon(
            Icons.folder_rounded,
            color: AppPalette.accent,
            semanticLabel: 'target',
          ),
          label: Text(p.basename(path)),
          selected: path == current,
          showCheckmark: false,
          onSelected: (_) => onPick(path),
        ),
    ],
  );
}
