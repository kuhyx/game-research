import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/finish_doc.dart';

import '../support/analysis_fakes.dart';

void main() {
  group('parseFinish', () {
    test('the four sections', () {
      final a = parseFinish(finishAnswer(), template: kTemplate);
      expect(a.merged, kDraft);
      expect(a.report, '# Report\nok\n');
      expect(a.task, 'Copy the tidy-up loop.\nAvoid the menu maze.');
      expect(a.check, 'make test');
    });

    test('a missing or empty task or check fails closed', () {
      const head = '@@@MERGED\n$kDraft@@@REPORT\n# R\n';
      for (final bad in [
        '$head@@@END\n',
        '$head@@@CHECK\nmake\n@@@END\n',
        '$head@@@TASK\n@@@CHECK\nmake\n@@@END\n',
        '$head@@@TASK\n  \nbody\n@@@END\n',
        '$head@@@TASK\nbody\n@@@CHECK\n\n@@@END\n',
        '$head@@@TASK\nbody\n@@@CHECK\nmake\n',
      ]) {
        expect(() => parseFinish(bad), throwsFormatException, reason: bad);
      }
    });

    test('a check over several lines is refused', () {
      expect(
        () => parseFinish(finishAnswer(check: 'make\nmake test')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('single line'),
          ),
        ),
      );
    });
  });

  test('repoFromRemote reads owner/name from https and scp remotes', () {
    expect(
      repoFromRemote('git@github.com:kuhyx/cleanup-plate.git\n'),
      'kuhyx/cleanup-plate',
    );
    expect(
      repoFromRemote('https://github.com/kuhyx/cleanup-plate'),
      'kuhyx/cleanup-plate',
    );
    expect(repoFromRemote('ssh://git@host/a/b.git'), 'a/b');
    for (final bad in [
      null,
      '',
      '  ',
      'cleanup-plate',
      'git@github.com:x',
      '/srv/x.git',
    ]) {
      expect(repoFromRemote(bad), isNull, reason: '$bad');
    }
  });

  test('the title is Apply <game> research to <repo name>', () {
    final t = finishTodoTitle('Librarian', 'kuhyx/cleanup-plate');
    expect(t, 'Apply Librarian research to cleanup-plate');
    expect(t, isNot(startsWith('MANUAL WORK REQUIRED')));
  });

  test('the prompt asks for the task and one-line check in the target', () {
    final prompt = buildFinishPrompt(
      game: 'Alpha',
      target: '/src/cleanup-plate',
      template: '/t.md',
      drafts: const [(stamp: '1', path: '/d.md')],
      markers: const [(stamp: '1', path: '/m.jsonl')],
    );
    expect(prompt, contains('MERGED ANSWERS'));
    expect(prompt, contains('/src/cleanup-plate'));
    expect(prompt, contains('CLAUDE.md'));
    final flat = prompt.replaceAll(RegExp(r'\s+'), ' ');
    for (final part in [
      'Answer first, one claim per bullet, no hedging',
      'at most 10 words',
      'at most 800 words',
      'quotes included',
      'ONE line',
      'Open: Q1.3, Q2.5',
    ]) {
      expect(flat, contains(part));
    }
    expect(prompt.indexOf(kTaskMarker), lessThan(prompt.indexOf(kCheckMarker)));
  });
}
