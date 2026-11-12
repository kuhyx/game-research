import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/discord_doc.dart';
import 'package:game_research/core/synthesis.dart';

void main() {
  test('the sibling of X.md is X.discord.md', () {
    expect(discordPathOf('/a/b/DOCS-r-g.md'), '/a/b/DOCS-r-g.discord.md');
    expect(isDiscordPath('/a/DOCS-r-g.discord.md'), isTrue);
    expect(isDiscordPath('/a/DOCS-r-g.md'), isFalse);
    expect(() => discordPathOf('/a/b.txt'), throwsArgumentError);
    expect(() => discordPathOf('/a/b.discord.md'), throwsArgumentError);
  });

  test('a sibling is never taken for a session draft', () {
    final name = RegExp(r'^DOCS-research-g-(\d{8}-\d{6})\.md$');
    final sibling = discordPathOf('/x/DOCS-research-g-20261112-090025.md');
    expect(name.hasMatch(sibling.split('/').last), isFalse);
  });

  test('the prompt names the doc, the limit, the rules and the envelope', () {
    final text = buildDiscordPrompt('/t/doc.md');
    expect(text, contains('/t/doc.md'));
    expect(text, contains('$kDiscordMax'));
    expect(text, contains('$kDiscordMarker\n'));
    expect(text, contains(kEndMarker));
    expect(text, contains('no tables'));
  });

  test('the rewrite prompt lists each violation and the long answer', () {
    final text = discordRewritePrompt(
      docPath: '/t/doc.md',
      longFile: '/w/long.txt',
      violations: ['discord: 2100 chars > 1900', 'discord: empty'],
      format: '$kDiscordMarker\n<x>\n$kEndMarker',
    );
    expect(text, contains('/w/long.txt'));
    expect(text, contains('/t/doc.md'));
    expect(text, contains('- discord: 2100 chars > 1900'));
    expect(text, contains('- discord: empty'));
  });

  group('parseDiscord', () {
    test('takes the lines between the markers, tidied', () {
      const raw = 'chatter\n$kDiscordMarker\n# T\n\n\n\n- a\n$kEndMarker\nmore';
      expect(parseDiscord(raw), '# T\n\n- a');
    });

    test('a missing marker throws', () {
      expect(() => parseDiscord('# T\n$kEndMarker'), throwsFormatException);
      expect(() => parseDiscord('$kDiscordMarker\n# T'), throwsFormatException);
    });

    test('an empty section parses to empty (violations name it)', () {
      expect(parseDiscord('$kDiscordMarker\n\n$kEndMarker'), '');
    });
  });

  group('discordViolations', () {
    test('a clean short doc has none', () {
      expect(discordViolations('# T\n## A\n### B\n- **x** y\ntext'), isEmpty);
    });

    test('exactly the limit passes, one more is named', () {
      expect(discordViolations('x' * kDiscordMax), isEmpty);
      expect(discordViolations('x' * (kDiscordMax + 1)), [
        'discord: ${kDiscordMax + 1} chars > $kDiscordMax',
      ]);
    });

    test('table rows are named by line', () {
      final v = discordViolations('# T\n| a | b |\n|---|---|\ntext\n  | c |');
      expect(v, ['discord: table rows at lines 2, 3, 5']);
    });

    test('headings deeper than ### are named by line', () {
      final v = discordViolations('# T\n#### A\n##### B\n### ok');
      expect(v, ['discord: heading deeper than ### at lines 2, 3']);
    });

    test('empty and blank are named', () {
      expect(discordViolations(''), ['discord: empty']);
      expect(discordViolations(' \n\n'), ['discord: empty']);
    });

    test('several kinds are all listed', () {
      final v = discordViolations('#### A\n| a |\n${'x' * 2000}');
      expect(v, hasLength(3));
    });
  });
}
