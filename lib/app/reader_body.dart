/// The reader body when there is no page to show: the loading ring, the
/// error glyph, and the raw-markdown editor (the one place that may scroll).
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/doc_style.dart';

/// The ring while loading, the error glyph after a failed load.
class ReaderPlaceholder extends StatelessWidget {
  /// For a window in [style]; [failed] picks the glyph.
  const new({required this.style, required this.failed, super.key});

  /// Sizes.
  final DocStyle style;

  /// The load failed.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    const failedSemantic = 'document error';
    return Center(
      child: failed
          ? Icon(
              Icons.error_outline_rounded,
              color: AppPalette.danger,
              size: style.px(192),
              semanticLabel: failedSemantic,
            )
          : const CircularProgressIndicator(),
    );
  }
}

/// The markdown source in the body face and colours.
class ReaderEditor extends StatelessWidget {
  /// Edits [controller]; [onChanged] runs on every keystroke.
  const new({
    required this.style,
    required this.controller,
    required this.onChanged,
    super.key,
  });

  /// Sizes.
  final DocStyle style;

  /// The text.
  final TextEditingController controller;

  /// A change was typed.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    const fieldSemantic = 'document text';
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: style.marginX,
        vertical: style.marginY,
      ),
      child: Semantics(
        label: fieldSemantic,
        child: TextField(
          controller: controller,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: style.editStyle,
          cursorColor: DocStyle.heading,
          decoration: const InputDecoration.collapsed(hintText: null),
          onChanged: (_) => onChanged(),
        ),
      ),
    );
  }
}
