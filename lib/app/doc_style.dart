/// Sizes, colours and spans of the document reader. Everything is specified
/// in physical pixels of a 3840-wide screen and converted to logical pixels
/// with the real viewport: size = phys * (physical width / 3840) / dpr.
library;

import 'package:flutter/painting.dart';
import 'package:game_research/app/doc_blocks.dart';
import 'package:game_research/core/doc_refs.dart';

/// The reference screen width the physical sizes are given for.
const double kReferenceWidth = 3840;

final _inline = RegExp(
  r'\*\*(.+?)\*\*|\*(\S(?:.*?\S)?)\*|(?<!\w)_(\S(?:.*?\S)?)_(?!\w)|`(.+?)`',
);

/// The reader's look at one viewport.
class DocStyle {
  /// For a window of [width] x [height] logical px at [dpr].
  new({required this.width, required this.height, required this.dpr});

  /// Dark page.
  static const background = Color(0xFF16181D);

  /// Body text.
  static const body = Color(0xFFD4D8DE);

  /// Headings (and bold runs).
  static const heading = Color(0xFFEEF0F3);

  /// References, open ids, bullets.
  static const muted = Color(0xFF98A0AB);

  /// `Answer` label.
  static const answer = Color(0xFF7DB8FF);

  /// `Evidence` label.
  static const evidence = Color(0xFFE3B866);

  /// `For <repo>` label.
  static const forRepo = Color(0xFF8FD19A);

  /// Logical width of the window.
  final double width;

  /// Logical height of the window.
  final double height;

  /// Device pixels per logical pixel.
  final double dpr;

  /// Logical px of [phys] reference pixels.
  double px(double phys) => phys * (width * dpr / kReferenceWidth) / dpr;

  /// Body font size.
  double get bodySize => px(36);

  /// Left and right page margin.
  double get marginX => px(96);

  /// Top and bottom page margin.
  double get marginY => px(72);

  /// Space between columns.
  double get gutter => px(72);

  /// Width of one of the 3 columns.
  double get columnWidth => (width - 2 * marginX - 2 * gutter) / 3;

  /// Height of a column.
  double get columnHeight => height - 2 * marginY;

  /// Hanging indent of a bullet.
  double indentOf(DocBlock b) => b.kind == BlockKind.bullet ? bodySize : 0;

  /// Space above [b] when it does not start a column.
  double spacingAbove(DocBlock b) => switch (b.kind) {
    BlockKind.h1 => 0,
    BlockKind.h2 => bodySize * 1.6,
    BlockKind.h3 || BlockKind.openIds => bodySize,
    BlockKind.paragraph || BlockKind.bullet || BlockKind.label => bodySize / 2,
  };

  TextStyle _base(double size, double weight, Color color) => TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    height: 1.4,
    color: color,
    fontVariations: [FontVariation('wght', weight)],
  );

  /// The text of [b], styled.
  TextSpan spanFor(DocBlock b) => switch (b.kind) {
    BlockKind.h1 => _runs(b.text, _base(px(60), 700, heading), strong: 700),
    BlockKind.h2 => _runs(b.text, _base(px(44), 650, heading), strong: 650),
    BlockKind.h3 => _runs(b.text, _base(bodySize, 600, heading)),
    BlockKind.openIds => TextSpan(
      text: b.text,
      style: _base(bodySize, 400, muted),
    ),
    BlockKind.bullet ||
    BlockKind.paragraph => _runs(b.text, _base(bodySize, 400, body)),
    BlockKind.label => _label(b),
  };

  /// The raw-markdown editor's style: the body face, same colours.
  TextStyle get editStyle => _base(bodySize, 400, body);

  /// The bullet glyph's style.
  TextStyle get bulletStyle => _base(bodySize, 400, muted);

  TextSpan _label(DocBlock b) {
    final colour = switch (b.label) {
      'Answer' => answer,
      'Evidence' => evidence,
      _ => forRepo,
    };
    final size = bodySize * 0.83;
    final head = _base(size, 650, colour).copyWith(letterSpacing: size * 0.06);
    return TextSpan(
      children: [
        TextSpan(text: b.label.toUpperCase(), style: head),
        TextSpan(text: ' ', style: _base(bodySize, 400, body)),
        _runs(b.text, _base(bodySize, 400, body)),
      ],
    );
  }

  TextSpan _runs(String text, TextStyle base, {double strong = 600}) {
    final out = <InlineSpan>[];
    var at = 0;
    for (final m in _inline.allMatches(text)) {
      out.addAll(_refs(text.substring(at, m.start), base));
      if (m.group(1) != null) {
        final bold = base.copyWith(
          fontVariations: [FontVariation('wght', strong)],
          color: base.color == body ? heading : base.color,
        );
        out.addAll(_refs(m.group(1)!, bold));
      } else if (m.group(4) != null) {
        final code = base.copyWith(
          fontFamily: 'monospace',
          fontSize: base.fontSize! * 0.92,
          color: muted,
        );
        out.add(TextSpan(text: m.group(4), style: code));
      } else {
        final italic = base.copyWith(fontStyle: FontStyle.italic);
        out.addAll(_refs(m.group(2) ?? m.group(3)!, italic));
      }
      at = m.end;
    }
    out.addAll(_refs(text.substring(at), base));
    return TextSpan(children: out);
  }

  /// [text] with its references split out, muted in tabular figures.
  List<InlineSpan> _refs(String text, TextStyle base) {
    final out = <InlineSpan>[];
    var at = 0;
    for (final m in refPattern.allMatches(text)) {
      if (m.start > at) {
        out.add(TextSpan(text: text.substring(at, m.start), style: base));
      }
      out.add(
        TextSpan(
          text: m.group(0),
          style: base.copyWith(
            color: muted,
            fontSize: base.fontSize! * 0.92,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
      at = m.end;
    }
    if (at < text.length) {
      out.add(TextSpan(text: text.substring(at), style: base));
    }
    return out;
  }
}
