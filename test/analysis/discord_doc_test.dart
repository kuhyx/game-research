import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/discord_doc.dart';
import 'package:game_research/analysis/job.dart';
import 'package:game_research/core/discord_doc.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:game_research/core/usage.dart';
import 'package:game_research/desktop/config.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

String _envelope(String text) => '$kDiscordMarker\n$text\n$kEndMarker\n';

void main() {
  late Directory dir;
  late String doc;
  late String work;
  late List<String> prompts;
  late List<String> answers;

  /// Answers [answers] in order; records each prompt's text.
  Future<String> ask(String prompt, String file) async {
    prompts.add(File(file).readAsStringSync());
    expect(prompt, prompts.last);
    return answers.removeAt(0);
  }

  File sibling() => File(discordPathOf(doc));

  setUp(() {
    dir = tempDir();
    doc = p.join(dir.path, 'docs', 'DOCS-research-g-20261112-090025.md');
    File(doc)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('# Long doc\n');
    work = p.join(dir.path, 'work');
    prompts = [];
    answers = [];
  });

  group('writeDiscord', () {
    test('passes first try: one call, sibling written', () async {
      answers = [_envelope('# Short\n- **a** b')];
      await writeDiscord(doc, ask, work);
      expect(prompts, hasLength(1));
      expect(prompts.single, contains(doc));
      expect(sibling().readAsStringSync(), '# Short\n- **a** b\n');
      expect(File(doc).readAsStringSync(), '# Long doc\n');
    });

    test('overwrites an older sibling', () async {
      sibling().writeAsStringSync('old');
      answers = [_envelope('# New')];
      await writeDiscord(doc, ask, work);
      expect(sibling().readAsStringSync(), '# New\n');
    });

    test('one rewrite naming the violation, then ok', () async {
      answers = [_envelope('x' * 2000), _envelope('# Short')];
      await writeDiscord(doc, ask, work);
      expect(prompts, hasLength(2));
      expect(prompts[1], contains('- discord: 2000 chars > $kDiscordMax'));
      expect(
        File(p.join(work, 'discord_long.txt')).readAsStringSync(),
        _envelope('x' * 2000),
      );
      expect(sibling().readAsStringSync(), '# Short\n');
    });

    test('a second bad answer throws and writes nothing', () async {
      answers = [_envelope('| a |'), _envelope('| b |\n#### c')];
      await expectLater(
        writeDiscord(doc, ask, work),
        throwsA(
          isA<StateError>().having(
            (e) => '$e',
            'message',
            allOf(contains('table rows'), contains('1900 characters')),
          ),
        ),
      );
      expect(prompts, hasLength(2));
      expect(sibling().existsSync(), isFalse);
    });

    test('an empty answer is named, then rewritten', () async {
      answers = [_envelope(''), _envelope('# Ok')];
      await writeDiscord(doc, ask, work);
      expect(prompts[1], contains('- discord: empty'));
    });

    test('an answer without the envelope throws', () async {
      answers = ['# no markers'];
      await expectLater(writeDiscord(doc, ask, work), throwsFormatException);
      expect(sibling().existsSync(), isFalse);
    });

    test('a missing document throws before any call', () async {
      File(doc).deleteSync();
      await expectLater(writeDiscord(doc, ask, work), throwsStateError);
      expect(prompts, isEmpty);
    });
  });

  group('discordOutcome', () {
    test('ok on success', () async {
      answers = [_envelope('# S')];
      expect(await discordOutcome(doc, ask, work), kDiscordOk);
    });

    test('a failure becomes one line, nothing thrown, no sibling', () async {
      answers = [_envelope('| a |'), _envelope('| b |')];
      final out = await discordOutcome(doc, ask, work);
      expect(out, startsWith('failed: discord: table rows'));
      expect(out, isNot(contains('\n')));
      expect(sibling().existsSync(), isFalse);
      expect(File(doc).readAsStringSync(), '# Long doc\n');
    });

    test('a usage limit is recorded too, and long reasons are cut', () async {
      Future<String> limited(String q, String f) async =>
          throw WaitingError('limit ${'z' * 400}');
      final out = await discordOutcome(doc, limited, work);
      expect(out, startsWith('failed: limit zzz'));
      expect(out.length, lessThanOrEqualTo(208));
    });
  });

  test('dropDiscord deletes the sibling and tolerates none', () {
    dropDiscord(doc);
    sibling().writeAsStringSync('x');
    dropDiscord(doc);
    expect(sibling().existsSync(), isFalse);
    expect(File(doc).existsSync(), isTrue);
  });

  group('askOpus', () {
    Config cfg(Map<String, String> extra) => testConfig(dir, extra: extra);

    test('the fake model: text back, usage reported', () async {
      final fake = FakeSys()..onRun = (c) => ok('answer');
      Usage? seen;
      final text = await askOpus(
        config: cfg({'GAME_RESEARCH_FAKE_LLM': '/fake/llm'}),
        sys: fake.sys,
        prompt: 'q',
        promptFile: '/p.txt',
        dirs: [dir.path],
        spent: (u) => seen = u,
      );
      expect(text, 'answer');
      expect(seen, isNotNull);
      expect(fake.of('/fake/llm').single.args, ['opus', '/p.txt']);
    });

    test('a usage limit waits, another error is a StateError', () async {
      var out = 'Claude AI usage limit reached';
      final fake = FakeSys()..onRun = (c) => bad(out);
      Future<String> call() => askOpus(
        config: cfg({'GAME_RESEARCH_FAKE_LLM': '/fake/llm'}),
        sys: fake.sys,
        prompt: 'q',
        promptFile: '/p.txt',
        dirs: [dir.path],
        spent: (_) {},
      );
      await expectLater(call(), throwsA(isA<WaitingError>()));
      out = 'boom';
      await expectLater(call(), throwsStateError);
    });

    test('Claude (no fake) runs claude -p with Read only', () async {
      const envelope =
          '{"type":"result","subtype":"success","is_error":false,'
          '"result":"hi","modelUsage":{"claude-opus":{}}}';
      final fake = FakeSys()..onRun = (c) => ok(envelope);
      final text = await askOpus(
        config: cfg({}),
        sys: fake.sys,
        prompt: 'the prompt',
        promptFile: '/p.txt',
        dirs: ['/w', '/t'],
        spent: (_) {},
      );
      expect(text, 'hi');
      final call = fake.calls.single;
      expect(call.args, containsAllInOrder(['-p', 'the prompt']));
      expect(call.args, containsAllInOrder(['--add-dir', '/w']));
    });
  });
}
