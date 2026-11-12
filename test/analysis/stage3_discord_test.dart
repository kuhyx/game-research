// The short Discord version of a session draft (stage 3): written next to the
// draft, and a failure of it never fails the job.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/stage3.dart';
import 'package:game_research/core/discord_doc.dart';
import 'package:game_research/core/sampling.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

final String _stamp = sessionStamp('20261112-090025-alpha');

const frames = [SampleFrame(t: 12, kind: FrameKind.marker, file: 'f_0002.png')];

void main() {
  late Fixture fx;
  late FakeSys fake;
  var llmReplyDiscord = kDiscordAnswer;
  var discordExit = 0;

  Future<Map<String, Object?>> run() => Stage3(
    fx.session.path,
    testConfig(
      fx.root,
      extra: {
        'GAME_RESEARCH_FAKE_LLM': '/fake/llm',
        'GAME_RESEARCH_TODO_CMD': 'faketodo --x',
      },
    ),
    fake.sys,
  ).run(fx.meta, frames);

  setUp(() {
    fx = Fixture();
    Directory(p.join(fx.session.path, 'analysis')).createSync();
    llmReplyDiscord = kDiscordAnswer;
    discordExit = 0;
    fake = FakeSys()
      ..onRun = (c) {
        switch (c.exe) {
          case '/fake/llm':
            final short = File(c.args[1]).readAsStringSync();
            if (short.contains(kDiscordMarker) && discordExit != 0) {
              return bad('Claude AI usage limit reached', discordExit);
            }
            return ok(llmReply(c, kAnswer, discord: llmReplyDiscord));
          case 'faketodo':
            return ok(' task-17\n');
        }
        return ok('git@github.com:kuhyx/cleanup-plate.git\n');
      };
  });

  test('the short version sits next to the draft, never as a draft', () async {
    final state = await run();
    final draft = draftPath(fx.target.path, 'alpha', _stamp);
    expect(state, containsPair('discord', 'ok'));
    expect(
      File(discordPathOf(draft)).readAsStringSync(),
      '# Short\n- **a** b\n',
    );
    expect(File(draft).readAsStringSync(), kDraft);
    expect(priorDrafts(fx.target.path, 'alpha'), [draft]);
    final prompt = fake.of('/fake/llm').last.args.last;
    expect(File(prompt).readAsStringSync(), contains(draft));
    expect(
      jsonDecode(fx.out('stage3.json').readAsStringSync()),
      containsPair('discord', 'ok'),
    );
  });

  test('a failed short version fails neither the job nor the doc', () async {
    llmReplyDiscord = '# not an envelope';
    final state = await run();
    final draft = draftPath(fx.target.path, 'alpha', _stamp);
    expect(state['discord'], startsWith('failed: FormatException'));
    expect(state, containsPair('todo', 'task-17'));
    expect(File(draft).readAsStringSync(), kDraft);
    expect(File(discordPathOf(draft)).existsSync(), isFalse);
    // Noted once: a rerun does not pay for it again.
    final calls = fake.of('/fake/llm').length;
    await run();
    expect(fake.of('/fake/llm'), hasLength(calls));
  });

  test(
    'a usage limit on the short version is noted, the job goes on',
    () async {
      discordExit = 1;
      final state = await run();
      expect(state['discord'], startsWith('failed: '));
      expect(state, containsPair('todo', 'task-17'));
    },
  );
}
