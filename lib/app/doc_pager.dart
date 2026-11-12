/// Cuts a document into screens: blocks are measured at column width and
/// packed top to bottom into column 1, then 2, then 3, then the next page.
/// Nothing scrolls, nothing is clipped.
library;

import 'package:flutter/painting.dart';
import 'package:game_research/app/doc_blocks.dart';
import 'package:game_research/app/doc_style.dart';

/// A block with its place in a column.
class PlacedBlock {
  /// The block, measured to [height] with [top] of space above it.
  const new(this.block, this.top, this.height);

  /// The block.
  final DocBlock block;

  /// Space above it (0 for the first block of a column).
  final double top;

  /// Height of its text at the column width.
  final double height;
}

/// One column of a page.
class DocColumn {
  /// An empty column.
  new();

  /// The blocks, top to bottom.
  final blocks = <PlacedBlock>[];

  /// Set when the only block is taller than the column; it is drawn scaled
  /// down to fit rather than clipped.
  bool oversized = false;

  /// Height used so far.
  double used = 0;
}

/// One screen: three columns.
class DocPage {
  /// A page of 3 empty columns.
  new() : columns = [DocColumn(), DocColumn(), DocColumn()];

  /// Left to right.
  final List<DocColumn> columns;

  /// All blocks in reading order.
  List<PlacedBlock> get blocks => [for (final c in columns) ...c.blocks];
}

double _measure(TextSpan span, double width) {
  final painter = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout(maxWidth: width);
  final h = painter.height;
  painter.dispose();
  return h;
}

/// Width the text of [b] gets in a column of [style].
double textWidth(DocStyle style, DocBlock b) =>
    style.columnWidth - style.indentOf(b);

/// The pages of [blocks] at [style]; always at least one.
List<DocPage> paginate(List<DocBlock> blocks, DocStyle style) {
  final heights = [
    for (final b in blocks) _measure(style.spanFor(b), textWidth(style, b)),
  ];
  final pages = [DocPage()];
  var col = 0;
  final room = style.columnHeight - 0.5; // layout rounding slack

  bool isHead(DocBlock b) =>
      b.kind == BlockKind.h1 ||
      b.kind == BlockKind.h2 ||
      b.kind == BlockKind.h3;

  double chainFrom(int i) =>
      heights[i] +
      (isHead(blocks[i]) && i + 1 < blocks.length
          ? style.spacingAbove(blocks[i + 1]) + chainFrom(i + 1)
          : 0);

  // A page is added when its first block lands, so none ends up empty.
  DocColumn current() {
    while (pages.length * 3 <= col) {
      pages.add(DocPage());
    }
    return pages[col ~/ 3].columns[col % 3];
  }

  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    var column = current();
    final empty = column.blocks.isEmpty;
    final top = empty ? 0.0 : style.spacingAbove(b);
    var need = top + heights[i];
    // A heading stays with what follows it: the chain of headings and the
    // first body block after them move to the next column together.
    final chain = chainFrom(i);
    if (chain <= room) need = top + chain;
    if (!empty && column.used + need > room) {
      col++;
      column = current();
    }
    final placedTop = column.blocks.isEmpty ? 0.0 : style.spacingAbove(b);
    column.blocks.add(PlacedBlock(b, placedTop, heights[i]));
    column.used += placedTop + heights[i];
    if (column.used > room) {
      column.oversized = true;
      col++;
    }
  }
  return pages;
}
