import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const _template = '''
# Research questions: {{GAME}}

### Q1.1 First?
- **Answer:** _(pending)_

### Q1.2 Second?
- **Answer:** _(pending)_
''';

String _doc(String s1, String s2) =>
    '''
# Research questions: Foo
### Q1.1 First?
- **Answer:** a
- **Status:** $s1

### Q1.2 Second?
- **Answer:** b
- **Status:** $s2
''';

void main() {
  group('parseDoc', () {
    test('reads the document between the marker lines', () {
      final doc = parseDoc(
        'Here you go:\n@@@DOC\n# Foo\nbody "quoted" {x}\n@@@END\nD: done',
      );
      expect(doc, '# Foo\nbody "quoted" {x}\n');
    });

    test('fails closed on a missing marker, empty or non-heading doc', () {
      for (final bad in [
        '@@@DOC\n# a',
        '@@@DOC\n@@@END',
        '@@@DOC\nno heading\n@@@END',
        '# a\n@@@END',
        'no markers at all',
      ]) {
        expect(() => parseDoc(bad), throwsFormatException, reason: bad);
      }
    });

    test('the document always ends with one newline', () {
      expect(parseDoc('@@@DOC\n# a\n\n\n@@@END\n'), '# a\n');
    });

    test('with a template every question needs one valid status line', () {
      expect(
        parseDoc(
          '@@@DOC\n${_doc('answered', 'open')}@@@END',
          template: _template,
        ),
        contains('Q1.2'),
      );
      for (final bad in [
        _doc('answered', 'maybe'),
        _doc('answered', 'open').replaceAll('### Q1.2', '### Q9.9'),
        '${_doc('answered', 'open')}- **Status:** open\n',
        _doc('answered', 'open').replaceFirst('- **Status:** answered\n', ''),
      ]) {
        expect(
          () => parseDoc('@@@DOC\n$bad@@@END', template: _template),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('question ids are read in order', () {
      expect(questionIds(_template), ['Q1.1', 'Q1.2']);
    });
  });

  test('the prompt names every input, the status rule and the contract', () {
    final prompt = buildSynthesisPrompt(
      game: 'Foo Game',
      session: '20261111-120000',
      template: '/t/DOCS-research-questions.md',
      earlier: const ['/g/DOCS-research-foo-game-20261110-100000.md'],
      captions: '/s/analysis/captions.jsonl',
      markers: '/s/markers.jsonl',
      stills: '/s/analysis/still.jsonl',
      frames: const ['/s/analysis/frames/f_0001.png'],
    );
    for (final part in [
      'Foo Game',
      '20261111-120000',
      'DOCS-research-questions.md',
      'DOCS-research-foo-game-20261110-100000.md',
      'captions.jsonl',
      'markers.jsonl',
      'still.jsonl',
      'f_0001.png',
      '- **Status:** answered',
      'copy forward',
      '250 lines',
      '@@@DOC',
      '@@@END',
    ]) {
      expect(prompt.replaceAll('\n  ', ' '), contains(part));
    }
    expect(prompt, isNot(contains('Polish')));
    expect(prompt, isNot(contains('@@@PL')));
  });

  test('the first session says there is nothing earlier', () {
    final prompt = buildSynthesisPrompt(
      game: 'g',
      session: 's',
      template: '/t',
      earlier: const [],
      captions: '/c',
      markers: '/m',
      stills: '/s',
      frames: const [],
    );
    expect(prompt, contains('(none: this is the first session)'));
  });

  test('paths: one draft per session under games/<slug>', () {
    const t = '/home/k/src/cleanup-plate';
    const base = '$t/docs/research/games/foo-game';
    expect(
      draftPath(t, 'foo-game', '20261112-090025'),
      '$base/DOCS-research-foo-game-20261112-090025.md',
    );
    expect(mergedPath(t, 'foo-game'), '$base/DOCS-research-foo-game.md');
    expect(reportPath(t, 'foo-game'), '$base/DOCS-research-foo-game-report.md');
    expect(gameDocsDir(t, 'foo-game'), base);
  });

  test('templatePaths names the questions template and its twin', () {
    final tp = templatePaths('/r');
    expect(tp.en, '/r/docs/research/DOCS-research-questions.md');
    expect(tp.pl, '/r/docs/research/DOCS-research-questions-pl.md');
    expect(templatePath('/r'), tp.en);
  });

  test('sessionStamp is the date-time prefix of the folder name', () {
    expect(
      sessionStamp('20261112-090025-librarian-tidy-up'),
      '20261112-090025',
    );
    expect(sessionStamp('odd-name'), 'odd-name');
  });

  test('priorDrafts: only other sessions of the same game, oldest first', () {
    final root = tempDir().path;
    final dir = Directory(gameDocsDir(root, 'foo'))
      ..createSync(recursive: true);
    for (final name in [
      'DOCS-research-foo-20261112-090025.md',
      'DOCS-research-foo-20261110-100000.md',
      'DOCS-research-foo.md',
      'DOCS-research-foo-report.md',
      'DOCS-research-foobar-20261111-100000.md',
      'notes.md',
    ]) {
      File(p.join(dir.path, name)).writeAsStringSync('# x\n');
    }
    expect(
      priorDrafts(root, 'foo', exceptStamp: '20261112-090025').map(p.basename),
      ['DOCS-research-foo-20261110-100000.md'],
    );
    expect(priorDrafts(root, 'foo'), hasLength(2));
    expect(priorDrafts(root, 'nothing'), isEmpty);
  });

  test('todoTaskTitle and done check name the game and the draft', () {
    expect(
      todoTaskTitle('Foo Game'),
      'MANUAL WORK REQUIRED: review Foo Game research draft',
    );
    expect(
      todoDoneCheck('foo-game', '20261112-090025'),
      'git ls-files --error-unmatch '
      'docs/research/games/foo-game/DOCS-research-foo-game-20261112-090025.md',
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
