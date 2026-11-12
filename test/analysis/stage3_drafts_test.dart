import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/job.dart';
import 'package:game_research/analysis/stage3.dart';
import 'package:game_research/core/sampling.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:game_research/desktop/config.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

final String _stamp = sessionStamp('20261112-090025-alpha');

const frames = [
  SampleFrame(t: 0, kind: FrameKind.scene, file: 'f_0001.png'),
  SampleFrame(t: 12, kind: FrameKind.marker, file: 'f_0002.png'),
];

void main() {
  late Fixture fx;
  late FakeSys fake;
  var remote = 'git@github.com:kuhyx/cleanup-plate.git\n';
  var todoExit = 0;
  var llmAnswer = kAnswer;
  var llmExit = 0;

  Config config([Map<String, String> extra = const {}]) => testConfig(
    fx.root,
    extra: {
      'GAME_RESEARCH_FAKE_LLM': '/fake/llm',
      'GAME_RESEARCH_TODO_CMD': 'faketodo --x',
      ...extra,
    },
  );

  Stage3 stage([Config? c]) => Stage3(fx.session.path, c ?? config(), fake.sys);

  Future<Map<String, Object?>> run([Config? c]) =>
      stage(c).run(fx.meta, frames);

  setUp(() {
    fx = Fixture();
    Directory(p.join(fx.session.path, 'analysis')).createSync();
    remote = 'git@github.com:kuhyx/cleanup-plate.git\n';
    todoExit = 0;
    llmAnswer = kAnswer;
    llmExit = 0;
    fake = FakeSys()
      ..onRun = (c) {
        switch (c.exe) {
          case '/fake/llm':
            return llmExit == 0 ? ok(llmAnswer) : bad('', llmExit);
          case 'git':
            return remote.isEmpty ? bad('no origin', 2) : ok(remote);
          case 'faketodo':
            return todoExit == 0
                ? ok(' task-17\n')
                : bad('db locked', todoExit);
        }
        return null;
      };
  });

  test(
    'an earlier session draft goes into the prompt, never overwritten',
    () async {
      final earlier =
          File(draftPath(fx.target.path, 'alpha', '20261110-100000'))
            ..createSync(recursive: true)
            ..writeAsStringSync(kDraft);
      await run();
      expect(earlier.readAsStringSync(), kDraft);
      final prompt = fx.out('synthesis_prompt.txt').readAsStringSync();
      expect(prompt, contains(earlier.path));
      expect(prompt, isNot(contains('DOCS-research-alpha-$_stamp.md')));
    },
  );

  test('every Opus call is counted, also the one that failed', () async {
    llmAnswer = '# no markers';
    await expectLater(run(), throwsA(isA<FormatException>()));
    final env = jsonEncode({
      'subtype': 'success',
      'is_error': false,
      'result': kAnswer,
      'usage': {'input_tokens': 100, 'output_tokens': 40},
      'total_cost_usd': 0.5,
    });
    fake.onRun = (c) => c.exe == 'timeout' ? ok(env) : ok('t-1');
    final cfg = testConfig(
      fx.root,
      extra: {'GAME_RESEARCH_TODO_CMD': 'faketodo'},
    );
    final first = await stage(cfg).run(fx.meta, frames);
    expect(first['tokens'], containsPair('in', 100));
    expect(first['cost_usd'], 0.5);
    final bad = jsonEncode({
      'subtype': 'success',
      'is_error': true,
      'result': 'Claude AI usage limit reached',
      'usage': {'input_tokens': 7},
      'total_cost_usd': 0.25,
    });
    fx.out('stage3.json').deleteSync();
    fake.onRun = (c) => c.exe == 'timeout' ? ok(bad) : ok('t-1');
    await expectLater(
      stage(cfg).run(fx.meta, frames),
      throwsA(isA<WaitingError>()),
    );
    final state = jsonDecode(fx.out('stage3.json').readAsStringSync()) as Map;
    expect(state['cost_usd'], 0.25);
    expect(state.containsKey('draft'), isFalse);
  });
}
