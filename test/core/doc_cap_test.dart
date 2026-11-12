import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/doc_cap.dart';
import 'package:game_research/core/synthesis.dart';

void main() {
  test('tidyDoc drops Why we ask lines and collapses blank runs', () {
    const raw = '# T\n\n\n\n### Q1\nWhy we ask: because\n- a\n\n\n- b\n';
    expect(tidyDoc(raw), '# T\n\n### Q1\n- a\n\n- b');
  });

  test('lineCount counts lines with or without a final newline', () {
    expect([lineCount(''), lineCount('a'), lineCount('a\nb\n')], [0, 1, 2]);
  });

  test('a parsed draft is tidied: no Why we ask, no repeated blanks', () {
    const answer =
        '$kDocMarker\n# D\n\n\n### Q1.1 x\nWhy we ask: y\n'
        '- **Status:** open\n$kEndMarker\n';
    expect(parseDoc(answer), '# D\n\n### Q1.1 x\n- **Status:** open\n');
  });

  test('the shorten prompt names the file, the sizes and the target', () {
    final text = shortenPrompt(
      longFile: '/x/long.txt',
      violations: ['draft: 301 lines > 250', 'Q1.1 Answer 31 > 22'],
      format: '@@@DOC\n<md>\n@@@END',
    );
    expect(text, contains('/x/long.txt'));
    expect(text, contains('- draft: 301 lines > 250'));
    expect(text, contains('- Q1.1 Answer 31 > 22'));
    expect(text, contains('at most 10 words'));
    expect(text, contains('at most $kShortenTo'));
    expect(text, contains('@@@DOC'));
  });
}
