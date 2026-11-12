import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/doc_refs.dart';

void main() {
  test('frame refs, mm:ss and session stamps are refs', () {
    final hits = [
      for (final m in refPattern.allMatches(
        'f_0013 (07:26), 1:02:03, s 20261111-185105, 22 words',
      ))
        m.group(0),
    ];
    expect(hits, ['f_0013', '07:26', '1:02:03', '20261111-185105']);
  });

  test('3-digit minutes and bare 6-digit stamp times are refs', () {
    final hits = [
      for (final m in refPattern.allMatches(
        '112:13 and 185105 14:13, 212541 f_0054, 1:02:03, '
        '20261111-185105',
      ))
        m.group(0),
    ];
    expect(hits, [
      '112:13',
      '185105',
      '14:13',
      '212541',
      'f_0054',
      '1:02:03',
      '20261111-185105',
    ]);
  });

  test('ordinary numbers are not refs', () {
    final hits = refPattern.allMatches(
      '10 words, 6/10 held, 3,072 px, 400 ms, in 2026, 1234 and 12345',
    );
    expect(hits, isEmpty);
  });

  test('word count leaves refs and punctuation-only tokens out', () {
    expect(proseWords('Green ghost f_0061 (30:07), 6/10 held — yes'), 5);
    expect(proseWords('   '), 0);
  });

  test('bullet labels: Answer, Evidence, Status, For <repo>', () {
    final m = labelLine.firstMatch('- **For cleanup-plate:** copy it')!;
    expect(m.group(1), 'For cleanup-plate');
    expect(m.group(2), 'copy it');
    expect(labelLine.hasMatch('- **Answer:** x'), isTrue);
    expect(labelLine.hasMatch('- plain bullet'), isFalse);
  });
}
