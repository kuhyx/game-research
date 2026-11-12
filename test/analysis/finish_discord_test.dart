// The short Discord version of a game's report (finish): written next to the
// report, cleared when the report is merged again, never fails the merge.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/finish.dart';
import 'package:game_research/core/discord_doc.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

const _report = '# Alpha: what kuhy learned\nGood.\n';
final String _answer = finishAnswer(report: _report);

void main() {
  late Fixture fx;
  late FakeSys fake;
  late String data;
  var short = ok(kDiscordAnswer);

  FinishRunner runner() => FinishRunner(
    'alpha',
    testConfig(
      fx.root,
      extra: {
        'GAME_RESEARCH_FAKE_LLM': '/fake/llm',
        'GAME_RESEARCH_TODO_CMD': 'faketodo',
      },
    ),
    fake.sys,
    recordingPoll: const Duration(milliseconds: 5),
  );

  /// Marks a session analysed: its draft exists and stage3 says so.
  void analysed(Directory session, {String stamp = '20261112-090025'}) {
    final draft = draftPath(fx.target.path, 'alpha', stamp);
    File(draft)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(kDraft);
    File(p.join(session.path, 'analysis', 'stage3.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'draft': draft, 'todo': 't'}));
  }

  Map<String, Object?> json(String name) =>
      jsonDecode(File(p.join(data, 'games', 'alpha', name)).readAsStringSync())
          as Map<String, Object?>;

  setUp(() {
    fx = Fixture();
    data = p.join(fx.root.path, 'data');
    short = ok(kDiscordAnswer);
    fake = FakeSys()
      ..onRun = (c) {
        switch (c.exe) {
          case '/fake/llm':
            return File(c.args[1]).readAsStringSync().contains(kDiscordMarker)
                ? short
                : ok(_answer);
          case 'faketodo':
            return ok('task-9\n');
        }
        return ok('git@github.com:kuhyx/cleanup-plate.git\n');
      };
  });

  test('the report gets a short version next to it', () async {
    analysed(fx.session);
    expect(await runner().run(), 0);
    final report = reportPath(fx.target.path, 'alpha');
    expect(json('finish.json')['report_discord'], 'ok');
    expect(
      File(discordPathOf(report)).readAsStringSync(),
      '# Short\n- **a** b\n',
    );
    final prompt = fake.of('/fake/llm').last.args.last;
    expect(File(prompt).readAsStringSync(), contains(report));
  });

  test(
    'a failed short version fails neither the merge nor the report',
    () async {
      analysed(fx.session);
      short = ok('# not an envelope');
      expect(await runner().run(), 0);
      final done = json('finish.json');
      expect(done['report_discord'], startsWith('failed: FormatException'));
      expect(done['state'], 'done');
      expect(done['todo'], 'task-9');
      final report = reportPath(fx.target.path, 'alpha');
      expect(File(report).readAsStringSync(), _report);
      expect(File(discordPathOf(report)).existsSync(), isFalse);
      // Noted once: a rerun with nothing new does not retry it.
      final calls = fake.calls.length;
      await runner().run();
      expect(fake.calls, hasLength(calls));
    },
  );

  test(
    're-merging clears the old short version, then writes a new one',
    () async {
      analysed(fx.session);
      await runner().run();
      final report = reportPath(fx.target.path, 'alpha');
      expect(File(discordPathOf(report)).existsSync(), isTrue);
      void addSession(String stamp) {
        final dir = Directory(p.join(data, '$stamp-alpha'))
          ..createSync(recursive: true);
        File(p.join(dir.path, 'session.json'))
            .writeAsStringSync(jsonEncode(fx.meta));
        analysed(dir, stamp: stamp);
      }

      addSession('20261113-100000');
      short = ok('# not an envelope');
      await runner().run();
      expect(json('finish.json')['report_discord'], startsWith('failed: '));
      expect(
        File(discordPathOf(report)).existsSync(),
        isFalse,
        reason: 'stale',
      );
      // New sessions again: the next merge's short version is fine.
      addSession('20261114-100000');
      short = ok(kDiscordAnswer);
      await runner().run();
      expect(json('finish.json')['report_discord'], 'ok');
      expect(File(discordPathOf(report)).existsSync(), isTrue);
    },
  );
}
