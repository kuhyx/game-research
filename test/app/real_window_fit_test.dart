import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/doc_blocks.dart';
import 'package:game_research/app/doc_page_view.dart';
import 'package:game_research/core/doc_refs.dart';
import 'package:game_research/core/doc_rules.dart';

import 'fake_wrapper.dart';
import 'reader_fixtures.dart';
import 'reader_helpers.dart';

/// The real window: Chrome --app, tiled on DP-2 (3840x2160) under i3. Measured
/// with `i3-msg -t get_tree`: workspace rect 3840x2137 (23 px i3bar at the
/// bottom), 22 px title bar and a 2 px border on each side, no tab strip:
/// client area 3836x2113 physical, at DPR 2.
const _physical = Size(3836, 2113);

/// A report of base + [extra] prose words (spread over the 24 bullets): H1,
/// 6 H2 sections, bullets with a bold lead and refs of the four real shapes,
/// one `Open:` line.
String _report(int extra) {
  final b = StringBuffer('# Research report: Sample Game\n\n')
    ..writeln('Session 20261111-185105, 112:13 long, 62 captioned frames.');
  var seed = 1;
  for (var s = 1; s <= 6; s++) {
    b.writeln('\n## $s. ${words(seed++, 3)}\n');
    for (var i = 0; i < 4; i++) {
      final last = s == 6 && i == 3;
      final n = 8 + extra ~/ 24 + (last ? extra % 24 : 0);
      b.writeln(
        '- **${words(seed++, 3)}:** ${words(seed++, n)} '
        '(f_${s * 100 + i * 7 + 13}, ${s + 9}${i + 1}:0$i) '
        '${words(seed++, 10)} (${180000 + s * 111} ${100 + i * 3}:1$s).',
      );
    }
  }
  b.writeln('\nOpen: Q1.3, Q2.5, Q3.1, Q4.4, Q5.2, Q6.6');
  return b.toString();
}

void main() {
  setUpAll(loadInter);
  setUp(() => readerPointer = null);

  testWidgets('a full-cap report fits one page in the real DP-2 window', (
    t,
  ) async {
    final base = _report(0);
    final text = _report(kReportWordCap - proseWords(base));

    expect(proseWords(text), kReportWordCap);
    expect(kReportWordCap, 650);
    final tokens = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final refs = tokens.where(refPattern.hasMatch).length / tokens.length;
    expect(refs, inInclusiveRange(0.09, 0.13));

    final w = FakeWrapper()..docs['/t/a.md'] = text;
    await openReader(t, w, size: _physical);
    expect(t.takeException(), isNull);
    expect(find.byType(DocColumnView), findsNWidgets(3));
    expect(blocksShown(t), parseDoc(text).length);
    await reveal(t);
    expect(pageOf(t), '1/1');
  });
}
