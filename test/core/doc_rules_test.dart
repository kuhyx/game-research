import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/doc_cap.dart';
import 'package:game_research/core/doc_rules.dart';

String _words(int n) => List.filled(n, 'w').join(' ');

String _doc({
  String head = 'First?',
  String answer = 'a',
  String evidence = 'f_0001',
  String forRepo = 'copy it',
}) =>
    '''
# Research: Alpha
### Q1.1 $head
- **Answer:** $answer
- **Status:** answered
- **Evidence:** $evidence
- **For cleanup-plate:** $forRepo
### Q1.2 Second?
- **Answer:** b
- **Status:** open
## Open threads
- ${_words(60)}
''';

void main() {
  group('question rules', () {
    test('a doc within every limit has no violations', () {
      expect(questionViolations(_doc()), isEmpty);
    });

    test('the limits are 10, 22, 14, 14 and 650', () {
      expect(
        [
          kQuestionWordCap,
          kAnswerWordCap,
          kEvidenceWordCap,
          kForWordCap,
          kReportWordCap,
        ],
        [10, 22, 14, 14, 650],
      );
    });

    test('a heading over 10 words names the question', () {
      expect(questionViolations(_doc(head: _words(10))), isEmpty);
      expect(questionViolations(_doc(head: _words(14))), [
        'Q1.1 question 14 > 10',
      ]);
    });

    test('answer, evidence and for-repo are capped one by one', () {
      final v = questionViolations(
        _doc(answer: _words(31), evidence: _words(15), forRepo: _words(20)),
      );
      expect(v, [
        'Q1.1 Answer 31 > 22',
        'Q1.1 Evidence 15 > 14',
        'Q1.1 For cleanup-plate 20 > 14',
      ]);
      expect(
        questionViolations(
          _doc(answer: _words(22), evidence: _words(14), forRepo: _words(14)),
        ),
        isEmpty,
      );
    });

    test('refs do not count, a wrapped bullet does', () {
      final refs = '${_words(14)} f_0013 07:26 20261111-185105';
      expect(questionViolations(_doc(evidence: refs)), isEmpty);
      final wrapped = _doc(answer: '${_words(15)}\n  ${_words(8)}');
      expect(questionViolations(wrapped), ['Q1.1 Answer 23 > 22']);
    });

    test('hedge words are whole words, any case; could is fine', () {
      final v = questionViolations(
        _doc(
          answer: 'It Might work, perhaps',
          evidence: 'probably f_0001',
          forRepo: 'this seems fine, and appears ok',
        ),
      );
      expect(v, [
        'Q1.1 Answer hedge "might"',
        'Q1.1 Answer hedge "perhaps"',
        'Q1.1 Evidence hedge "probably"',
        'Q1.1 For cleanup-plate hedge "seems"',
        'Q1.1 For cleanup-plate hedge "appears"',
      ]);
      expect(
        questionViolations(_doc(answer: 'unlikely, but it could work')),
        isEmpty,
      );
    });

    test('text under a later heading is not charged to the last question', () {
      expect(questionViolations(_doc()), isEmpty); // 60 words in Open threads
    });

    test('a status line and a plain bullet are not limited', () {
      final doc = '### Q9.9 x\n- **Answer:** a\n- ${_words(40)}\n';
      expect(questionViolations(doc), isEmpty);
    });
  });

  group('lines and report', () {
    test('a document over 250 lines names itself', () {
      expect(lineViolations('draft', 'x\n' * 250), isEmpty);
      expect(lineViolations('draft', 'x\n' * 301), ['draft: 301 lines > 250']);
    });

    test('a report over 650 prose words says so; refs are free', () {
      expect(reportViolations('# R\n${_words(649)} f_0001 07:26\n'), isEmpty);
      expect(reportViolations('# R\n${_words(649)}\n'), isEmpty);
      expect(reportViolations('# R\n${_words(650)}\n'), [
        'report: 651 words > 650',
      ]);
    });

    test('a long report also reports its lines', () {
      expect(reportViolations('# R\n${'w\n' * 260}'), [
        'report: 261 lines > 250',
      ]);
    });

    test('docViolations is lines plus question rules, lines first', () {
      final doc = '${_doc(answer: _words(30))}${'x\n' * 260}';
      expect(docViolations('merged answers', doc), [
        'merged answers: 271 lines > 250',
        'Q1.1 Answer 30 > 22',
      ]);
    });
  });

  group('prompt text', () {
    test('the writing rules name every limit and hedge word', () {
      for (final part in [
        'Answer first, one claim per bullet, no hedging',
        'probably, likely, perhaps, maybe, seems, seem, appears, appear, might',
        'at most 10 words',
        'at most 22 words',
        'at most 14 words',
        'f_0013',
      ]) {
        expect(kWritingRules.replaceAll('\n', ' '), contains(part));
      }
    });
  });
}
