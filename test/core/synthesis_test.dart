import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/synthesis.dart';

void main() {
  group('parseSynthesis', () {
    const good =
        'Here you go:\n@@@EN\n# Research questions: Foo\nbody "quoted" {x}\n'
        '@@@PL\n# Pytania: Foo\ntresc\n@@@END\nD: done';

    test('reads the en and pl documents between the marker lines', () {
      final docs = parseSynthesis(good);
      expect(docs.en, '# Research questions: Foo\nbody "quoted" {x}\n');
      expect(docs.pl, '# Pytania: Foo\ntresc\n');
    });

    test('fails closed on a missing marker, empty or non-heading doc', () {
      for (final bad in [
        '@@@EN\n# a\n@@@END',
        '@@@EN\n# a\n@@@PL\n@@@END',
        '@@@EN\nno heading\n@@@PL\n# b\n@@@END',
        '@@@EN\n# a\n@@@PL\n# b',
        '@@@PL\n# b\n@@@EN\n# a\n@@@END',
        'no markers at all',
      ]) {
        expect(() => parseSynthesis(bad), throwsFormatException, reason: bad);
      }
    });

    test('documents always end with one newline', () {
      final docs = parseSynthesis('@@@EN\n# a\n\n\n@@@PL\n# b\n@@@END\n');
      expect(docs.en, '# a\n');
      expect(docs.pl, '# b\n');
    });
  });

  test('the prompt names every input and the output contract', () {
    final prompt = buildSynthesisPrompt(
      game: 'Foo Game',
      session: '20261111-120000-foo-game',
      templateEn: '/t/DOCS-research-questions.md',
      templatePl: '/t/DOCS-research-questions-pl.md',
      captions: '/s/analysis/captions.jsonl',
      markers: '/s/markers.jsonl',
      stills: '/s/analysis/still.jsonl',
      frames: const ['/s/analysis/frames/f_0001.png'],
    );
    for (final part in [
      'Foo Game',
      '20261111-120000-foo-game',
      'DOCS-research-questions.md',
      'DOCS-research-questions-pl.md',
      'captions.jsonl',
      'markers.jsonl',
      'still.jsonl',
      'f_0001.png',
      '@@@EN',
      '@@@PL',
      '@@@END',
    ]) {
      expect(prompt, contains(part));
    }
  });

  test('draftPaths puts both docs under docs/research', () {
    final p = draftPaths('/home/k/src/cleanup-plate', 'foo-game');
    expect(
      p.en,
      '/home/k/src/cleanup-plate/docs/research/'
      'DOCS-research-foo-game.md',
    );
    expect(p.pl, endsWith('DOCS-research-foo-game-pl.md'));
  });

  test('templatePaths names the questions template and its twin', () {
    final p = templatePaths('/r');
    expect(p.en, '/r/docs/research/DOCS-research-questions.md');
    expect(p.pl, '/r/docs/research/DOCS-research-questions-pl.md');
  });

  test('todoTaskTitle and done check name the game and the draft', () {
    expect(
      todoTaskTitle('Foo Game'),
      'MANUAL WORK REQUIRED: review Foo Game research draft',
    );
    expect(
      todoDoneCheck('foo-game'),
      'git ls-files --error-unmatch docs/research/DOCS-research-foo-game.md',
    );
  });

  test('repoSlugFromRemote maps any origin to kuhyx/<name>', () {
    expect(
      repoSlugFromRemote('git@github.com:someone/cleanup-plate.git', 'x'),
      'kuhyx/cleanup-plate',
    );
    expect(
      repoSlugFromRemote('https://github.com/kuhyx/todo', 'x'),
      'kuhyx/todo',
    );
    expect(repoSlugFromRemote(null, 'game-research'), 'kuhyx/game-research');
    expect(repoSlugFromRemote('  ', 'dir'), 'kuhyx/dir');
  });
}
