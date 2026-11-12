/// Draws one page of the reader: three columns of measured blocks. The text
/// is laid out exactly as the pager measured it (same span, same width,
/// no text scaling), so nothing overflows.
library;

import 'package:flutter/widgets.dart';
import 'package:game_research/app/doc_blocks.dart';
import 'package:game_research/app/doc_pager.dart';
import 'package:game_research/app/doc_style.dart';

/// One screen of the document.
class DocPageView extends StatelessWidget {
  /// Draws [page] in [style].
  const new({required this.page, required this.style, super.key});

  /// The page.
  final DocPage page;

  /// The look.
  final DocStyle style;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DocStyle.background,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: style.marginX,
          vertical: style.marginY,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < page.columns.length; i++) ...[
              if (i > 0) SizedBox(width: style.gutter),
              DocColumnView(column: page.columns[i], style: style),
            ],
          ],
        ),
      ),
    );
  }
}

/// One column.
class DocColumnView extends StatelessWidget {
  /// Draws [column] in [style].
  const new({required this.column, required this.style, super.key});

  /// The column.
  final DocColumn column;

  /// The look.
  final DocStyle style;

  @override
  Widget build(BuildContext context) {
    final stack = SizedBox(
      width: style.columnWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in column.blocks)
            Padding(
              padding: EdgeInsets.only(top: p.top),
              child: DocBlockView(block: p.block, style: style),
            ),
        ],
      ),
    );
    return SizedBox(
      width: style.columnWidth,
      height: style.columnHeight,
      child: column.oversized
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: stack,
            )
          : Align(alignment: Alignment.topLeft, child: stack),
    );
  }
}

/// One block of text.
class DocBlockView extends StatelessWidget {
  /// Draws [block] in [style].
  const new({required this.block, required this.style, super.key});

  /// The block.
  final DocBlock block;

  /// The look.
  final DocStyle style;

  @override
  Widget build(BuildContext context) {
    final text = RichText(text: style.spanFor(block));
    final indent = style.indentOf(block);
    if (indent == 0) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: indent,
          child: RichText(
            text: TextSpan(text: '•', style: style.bulletStyle),
          ),
        ),
        Expanded(child: text),
      ],
    );
  }
}
