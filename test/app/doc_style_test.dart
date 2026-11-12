import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/doc_blocks.dart';
import 'package:game_research/app/doc_style.dart';

DocStyle _style({double w = 1920, double h = 1080, double dpr = 2}) =>
    DocStyle(width: w, height: h, dpr: dpr);

List<TextSpan> _leaves(InlineSpan s) {
  final out = <TextSpan>[];
  s.visitChildren((c) {
    if (c is TextSpan && c.text != null) out.add(c);
    return true;
  });
  return out;
}

double? _wght(TextStyle? s) =>
    s?.fontVariations?.singleWhere((v) => v.axis == 'wght').value;

void main() {
  test('sizes are physical px over dpr, linear in the physical width', () {
    final s = _style();
    expect(s.bodySize, 18);
    expect(s.marginX, 48);
    expect(s.marginY, 36);
    expect(s.gutter, 36);
    expect(s.columnWidth, (1920 - 96 - 72) / 3);
    expect(s.columnHeight, 1080 - 72);
    final one = _style(w: 3840, h: 2160, dpr: 1);
    expect(one.bodySize, 36);
    expect(one.columnWidth, (3840 - 192 - 144) / 3);
    final half = _style(w: 960, h: 540, dpr: 1);
    expect(half.bodySize, 9);
  });

  test('headings: 60/700, 44/650, 36/600 in the heading colour', () {
    final s = _style(w: 3840, h: 2160, dpr: 1);
    final h1 = _leaves(s.spanFor(const DocBlock(BlockKind.h1, 'T'))).single;
    final h2 = _leaves(s.spanFor(const DocBlock(BlockKind.h2, 'T'))).single;
    final h3 = _leaves(s.spanFor(const DocBlock(BlockKind.h3, 'T'))).single;
    expect([h1.style!.fontSize, _wght(h1.style)], [60, 700]);
    expect([h2.style!.fontSize, _wght(h2.style)], [44, 650]);
    expect([h3.style!.fontSize, _wght(h3.style)], [36, 600]);
    expect(h1.style!.color, DocStyle.heading);
    expect(h1.style!.height, 1.4);
    expect(h1.style!.fontFamily, 'Inter');
  });

  test('refs are muted tabular figures at 0.92 em', () {
    final s = _style(w: 3840, h: 2160, dpr: 1);
    final leaves = _leaves(
      s.spanFor(const DocBlock(BlockKind.paragraph, 'see f_0013 at 07:26 ok')),
    );
    expect(leaves.map((l) => l.text), [
      'see ',
      'f_0013',
      ' at ',
      '07:26',
      ' ok',
    ]);
    final ref = leaves[1].style!;
    expect(ref.color, DocStyle.muted);
    expect(ref.fontSize, closeTo(36 * 0.92, 1e-9));
    expect(ref.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(leaves[0].style!.color, DocStyle.body);
    expect(leaves[0].style!.fontFeatures, isNull);
  });

  test('labels: caps, 0.83 em, 650, +0.06 em, their colour', () {
    final s = _style(w: 3840, h: 2160, dpr: 1);
    final colours = {
      for (final l in ['Answer', 'Evidence', 'For cleanup-plate'])
        l: _leaves(s.spanFor(DocBlock(BlockKind.label, 'text', label: l)))
            .first
            .style!
            .color,
    };
    expect(colours, {
      'Answer': const Color(0xFF7DB8FF),
      'Evidence': const Color(0xFFE3B866),
      'For cleanup-plate': const Color(0xFF8FD19A),
    });
    final leaves = _leaves(
      s.spanFor(const DocBlock(BlockKind.label, 'text', label: 'For x-y')),
    );
    expect(leaves.first.text, 'FOR X-Y');
    final st = leaves.first.style!;
    expect(st.fontSize, closeTo(36 * 0.83, 1e-9));
    expect(st.letterSpacing, closeTo(36 * 0.83 * 0.06, 1e-9));
    expect(_wght(st), 650);
    expect(leaves.last.text, 'text');
    expect(leaves.last.style!.color, DocStyle.body);
  });

  test('bold, italic and code runs; headings keep their weight', () {
    final s = _style(w: 3840, h: 2160, dpr: 1);
    final p = _leaves(
      s.spanFor(
        const DocBlock(BlockKind.paragraph, 'a **b** *c* _d_ `e` f_01 g'),
      ),
    );
    expect(p.map((l) => l.text).join(), 'a b c d e f_01 g');
    final byText = {for (final l in p) l.text!: l.style!};
    expect(_wght(byText['b']), 600);
    expect(byText['c']!.fontStyle, FontStyle.italic);
    expect(byText['d']!.fontStyle, FontStyle.italic);
    expect(byText['e']!.fontFamily, 'monospace');
    final h = _leaves(s.spanFor(const DocBlock(BlockKind.h1, 'X **y**')));
    expect(h.map((l) => _wght(l.style)), everyElement(700));
  });

  test('spacing above blocks and the bullet indent', () {
    final s = _style(w: 3840, h: 2160, dpr: 1);
    double sp(BlockKind k) => s.spacingAbove(DocBlock(k, 'x'));
    expect(sp(BlockKind.bullet), 18);
    expect(sp(BlockKind.label), 18);
    expect(sp(BlockKind.h3), 36);
    expect(sp(BlockKind.openIds), 36);
    expect(sp(BlockKind.h2), closeTo(36 * 1.6, 1e-9));
    expect(sp(BlockKind.paragraph), 18);
    expect(sp(BlockKind.h1), 0);
    expect(s.indentOf(const DocBlock(BlockKind.bullet, 'x')), 36);
    expect(s.indentOf(const DocBlock(BlockKind.paragraph, 'x')), 0);
  });
}
