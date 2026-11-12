/// The writing rules of the research documents and the pure check that holds
/// Opus to them (kuhy, 2026-11-12: a reader shows a document at 4K without
/// scrolling). The prompts state the rules ([kWritingRules]); this file counts
/// the per-question ones, so code adjudicates and a break is a named
/// violation, never a guess. `doc_cap.dart` adds the line and report caps.
library;

import 'package:game_research/core/doc_refs.dart';

/// Words a question heading may have after its `Q1.2` id.
const kQuestionWordCap = 10;

/// Prose words of an `- **Answer:**` bullet.
const kAnswerWordCap = 22;

/// Prose words of an `- **Evidence:**` bullet.
const kEvidenceWordCap = 14;

/// Prose words of a `- **For <repo>:**` bullet.
const kForWordCap = 14;

/// Prose words of a whole report.
const kReportWordCap = 800;

/// Hedges a question bullet must not use (whole words, any case). `could` is
/// allowed.
const kHedgeWords = [
  'probably',
  'likely',
  'perhaps',
  'maybe',
  'seems',
  'seem',
  'appears',
  'appear',
  'might',
];

final _hedge = RegExp('\\b(${kHedgeWords.join('|')})\\b', caseSensitive: false);

/// A question heading: group 1 the id, group 2 the text after it.
final _questionHead = RegExp(r'^### (Q\d+(?:\.\d+)*)\b(.*)$');

/// The rules as the prompts of both Opus calls state them.
final String kWritingRules =
    '''
Writing rules (code checks every one; a break costs a rewrite):
- Answer first, one claim per bullet, no hedging. Never use these words:
  ${kHedgeWords.join(', ')}.
- Keep every question's `### Q1.2` id, but reword the question text after it
  to at most $kQuestionWordCap words.
- Per question: `- **Answer:**` at most $kAnswerWordCap words,
  `- **Evidence:**` at most $kEvidenceWordCap words, `- **For <repo>:**` at
  most $kForWordCap words. Frame files (f_0013), mm:ss offsets and session
  stamps do not count as words.
- Evidence is refs (frame files, mm:ss offsets, session stamps), not long
  quotes; verbatim quotes of kuhy's markers belong in the report.''';

/// Breaks of the per-question rules in [doc]: heading, Answer, Evidence and
/// For bullets over their word caps, and hedge words in those bullets. A
/// bullet runs to the next bullet or heading, so wrapped lines count.
List<String> questionViolations(String doc) {
  final out = <String>[];
  String? id;
  String? label;
  var text = '';
  void flush() {
    final cap = switch (label) {
      'Answer' => kAnswerWordCap,
      'Evidence' => kEvidenceWordCap,
      final l? when l.startsWith('For ') => kForWordCap,
      _ => null,
    };
    if (id != null && cap != null) {
      final n = proseWords(text);
      if (n > cap) out.add('$id $label $n > $cap');
      final seen = <String>{};
      for (final m in _hedge.allMatches(text)) {
        final word = m.group(1)!.toLowerCase();
        if (seen.add(word)) out.add('$id $label hedge "$word"');
      }
    }
    label = null;
    text = '';
  }

  for (final line in doc.split('\n')) {
    final head = _questionHead.firstMatch(line);
    final bullet = labelLine.firstMatch(line);
    if (head != null || line.startsWith('#') || line.startsWith('- ')) flush();
    if (head != null) {
      id = head.group(1);
      final n = proseWords(head.group(2)!);
      if (n > kQuestionWordCap) out.add('$id question $n > $kQuestionWordCap');
    } else if (line.startsWith('#')) {
      id = null;
    } else if (bullet != null) {
      label = bullet.group(1);
      text = bullet.group(2)!;
    } else if (label != null) {
      text = '$text $line';
    }
  }
  flush();
  return out;
}
