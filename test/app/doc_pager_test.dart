import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/doc_blocks.dart';
import 'package:game_research/app/doc_pager.dart';
import 'package:game_research/app/doc_style.dart';

import 'reader_fixtures.dart';

DocStyle _style({double w = 1920, double h = 1080, double dpr = 2}) =>
    DocStyle(width: w, height: h, dpr: dpr);

void main() {
  setUpAll(loadInter);

  for (final (w, h, dpr) in [(1920.0, 1080.0, 2.0), (3840.0, 2160.0, 1.0)]) {
    test('the ~800-word report is one page of 3 columns at ${w}x$h', () {
      final text = reportFixture();
      expect(wordCount(text), inInclusiveRange(750, 850));
      final pages = paginate(parseDoc(text), _style(w: w, h: h, dpr: dpr));
      expect(pages, hasLength(1));
      expect(pages.single.columns, hasLength(3));
      expect(pages.single.columns.where((c) => c.blocks.isNotEmpty).length, 3);
    });
  }

  test('the ~3,500-word draft pages; every block once, in order', () {
    final blocks = parseDoc(draftFixture());
    final pages = paginate(blocks, _style());
    expect(pages.length, greaterThanOrEqualTo(3));
    final placed = [for (final p in pages) ...p.blocks];
    expect(placed.length, blocks.length);
    for (var i = 0; i < blocks.length; i++) {
      expect(identical(placed[i].block, blocks[i]), isTrue, reason: '#$i');
    }
    for (final p in pages) {
      for (final c in p.columns) {
        var used = 0.0;
        for (final b in c.blocks) {
          used += b.top + b.height;
        }
        expect(used, lessThanOrEqualTo(_style().columnHeight));
      }
    }
  });

  test('a heading never ends a column when more text follows', () {
    final blocks = parseDoc(draftFixture());
    final pages = paginate(blocks, _style());
    for (final p in pages) {
      for (final c in p.columns) {
        if (c.blocks.isEmpty) continue;
        final last = c.blocks.last.block;
        final isDocEnd = identical(last, blocks.last);
        final heading = const {
          BlockKind.h1,
          BlockKind.h2,
          BlockKind.h3,
        }.contains(last.kind);
        expect(heading && !isDocEnd, isFalse, reason: last.text);
      }
    }
  });

  test('a block taller than a column keeps a column to itself', () {
    final blocks = [
      const DocBlock(BlockKind.h2, 'before'),
      DocBlock(BlockKind.paragraph, words(5, 2500)),
      const DocBlock(BlockKind.paragraph, 'after'),
    ];
    final pages = paginate(blocks, _style());
    final big = pages
        .expand((p) => p.columns)
        .singleWhere((c) => c.blocks.any((b) => b.block == blocks[1]));
    expect(big.blocks, hasLength(1));
    expect(big.oversized, isTrue);
    expect(big.blocks.single.height, greaterThan(_style().columnHeight));
    expect([for (final p in pages) ...p.blocks], hasLength(3));
  });

  test('an empty document is one empty page', () {
    final pages = paginate(const [], _style());
    expect(pages, hasLength(1));
    expect(pages.single.blocks, isEmpty);
  });
}
