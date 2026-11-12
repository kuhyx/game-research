import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/doc_blocks.dart';

import 'reader_fixtures.dart';

List<BlockKind> _kinds(String md) => [for (final b in parseDoc(md)) b.kind];

void main() {
  test('headings, paragraphs and bullets become blocks', () {
    final blocks = parseDoc(
      '# One\n\n## Two\n### Three\nline a\nline b\n\n- x\n  more\n- y\n',
    );
    expect(_kinds('# One\n## Two\n### Three'), [
      BlockKind.h1,
      BlockKind.h2,
      BlockKind.h3,
    ]);
    expect(blocks[3].kind, BlockKind.paragraph);
    expect(blocks[3].text, 'line a line b');
    expect(blocks[4].kind, BlockKind.bullet);
    expect(blocks[4].text, 'x more');
    expect(blocks[5].text, 'y');
    expect(blocks, hasLength(6));
  });

  test('comments, rules and blank lines are skipped', () {
    expect(_kinds('<!-- a -->\n<!--\nb\n-->\n---\n\ntext'), [
      BlockKind.paragraph,
    ]);
  });

  test('labelled bullets keep the label; the status line is hidden', () {
    final blocks = parseDoc(
      '- **Answer:** yes\n- **Status:** answered\n'
      '- **Evidence:** f_0013\n- **For cleanup-plate:** use it\n',
    );
    expect(blocks.map((b) => b.kind), everyElement(BlockKind.label));
    expect(blocks.map((b) => b.label), [
      'Answer',
      'Evidence',
      'For cleanup-plate',
    ]);
    expect(blocks.map((b) => b.text), ['yes', 'f_0013', 'use it']);
  });

  test('open questions collapse into one ids line at the first', () {
    final blocks = parseDoc(
      '## A\n### Q1.1 first\n- **Answer:** a\n- **Status:** answered\n'
      '### Q1.2 second\n- **Answer:** _(pending)_\n- **Status:** open\n'
      '### Q2.5 third\n- **Status:** partial\n- **Answer:** half\n'
      '## B\n### Q2.6 fourth\n- **Status:** open\n'
      '- **Evidence:** _(pending)_\n',
    );
    expect(blocks.map((b) => b.kind), [
      BlockKind.h2,
      BlockKind.h3,
      BlockKind.label,
      BlockKind.openIds,
      BlockKind.h3,
      BlockKind.label,
      BlockKind.h2,
    ]);
    final ids = blocks.singleWhere((b) => b.kind == BlockKind.openIds);
    expect(ids.text, 'Q1.2 · Q2.6');
    expect(blocks.where((b) => b.text.contains('second')), isEmpty);
  });

  test('no open question: no ids line; a plain ### stays', () {
    final blocks = parseDoc(
      '### Notes\ntext\n### Q1.1 x\n- **Status:** partial',
    );
    expect(blocks.map((b) => b.kind), [
      BlockKind.h3,
      BlockKind.paragraph,
      BlockKind.h3,
    ]);
  });

  test('the draft fixture collapses its open questions', () {
    final blocks = parseDoc(draftFixture());
    final ids = blocks.singleWhere((b) => b.kind == BlockKind.openIds);
    expect(ids.text.split(' · '), hasLength(8));
    expect(blocks.where((b) => b.label == 'Status'), isEmpty);
    expect(wordCount(draftFixture()), inInclusiveRange(3200, 3900));
  });
}
