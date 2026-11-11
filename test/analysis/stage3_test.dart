import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/stage3.dart';
import 'package:game_research/core/sampling.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:game_research/desktop/config.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

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

  test('fake model: drafts written, one todo task, state saved', () async {
    final state = await run();
    final drafts = draftPaths(fx.target.path, 'alpha');
    expect(File(drafts.en).readAsStringSync(), '# English\nbody\n');
    expect(File(drafts.pl).readAsStringSync(), '# Polski\ntresc\n');
    expect(state, containsPair('draft_en', drafts.en));
    expect(state, containsPair('model', 'fake:opus'));
    expect(state, containsPair('frames', 1));
    expect(state, containsPair('todo', 'task-17'));
    expect(
      fx.out('synthesis_prompt.txt').readAsStringSync(),
      contains('f_0002.png'),
    );
    final llm = fake.of('/fake/llm').single;
    expect(llm.args, ['opus', fx.out('synthesis_prompt.txt').path]);
    final todo = fake.of('faketodo').single;
    expect(
      todo.args,
      containsAllInOrder(['--x', '--repo', 'kuhyx/cleanup-plate']),
    );
    expect(todo.args, containsAllInOrder(['--new-note', '--by', 'claude']));
    expect(todo.args.last, contains('review Alpha research draft'));
    expect(todo.cwd, p.join(fx.root.path, 'src', 'todo'));
    expect(
      jsonDecode(fx.out('stage3.json').readAsStringSync()),
      containsPair('todo', 'task-17'),
    );
  });

  test('a finished state costs nothing on rerun', () async {
    await run();
    final calls = fake.calls.length;
    final again = await run();
    expect(fake.calls, hasLength(calls));
    expect(again, containsPair('todo', 'task-17'));
  });

  test('a failed todo call is retried without a second model call', () async {
    todoExit = 5;
    await expectLater(
      run(),
      throwsA(
        isA<StateError>().having(
          (e) => '$e',
          'text',
          contains('todo task failed (5): db locked'),
        ),
      ),
    );
    final state = jsonDecode(fx.out('stage3.json').readAsStringSync()) as Map;
    expect(state.containsKey('todo'), isFalse);
    todoExit = 0;
    await run();
    expect(fake.of('/fake/llm'), hasLength(1));
    expect(fake.of('faketodo'), hasLength(2));
  });

  test(
    'the repo slug falls back to the folder name without an origin',
    () async {
      remote = '';
      await run();
      expect(fake.of('faketodo').single.args, contains('kuhyx/cleanup-plate'));
    },
  );

  test('missing templates fail before any model call', () async {
    File(templatePaths(fx.target.path).pl).deleteSync();
    await expectLater(run(), throwsA(isA<StateError>()));
    expect(fake.calls, isEmpty);
  });

  test('a failing fake model, or a malformed answer, writes nothing', () async {
    llmExit = 3;
    await expectLater(
      run(),
      throwsA(
        isA<StateError>().having((e) => '$e', 'text', contains('exit 3')),
      ),
    );
    llmExit = 0;
    llmAnswer = '# no markers';
    await expectLater(run(), throwsA(isA<FormatException>()));
    expect(File(draftPaths(fx.target.path, 'alpha').en).existsSync(), isFalse);
  });

  test(
    'real Opus call: claude -p with the session and target readable',
    () async {
      final env = jsonEncode({
        'subtype': 'success',
        'is_error': false,
        'result': kAnswer,
        'modelUsage': {'claude-opus-4-8': <String, Object>{}},
      });
      fake.onRun = (c) {
        if (c.exe == 'timeout') return ok(env);
        if (c.exe == 'faketodo') return ok('t-1');
        return bad();
      };
      final cfg = testConfig(
        fx.root,
        extra: {'GAME_RESEARCH_TODO_CMD': 'faketodo'},
      );
      final state = await stage(cfg)
          .run({...fx.meta}..remove('duration_s'), frames);
      expect(state, containsPair('model', 'claude-opus-4-8'));
      final call = fake.of('timeout').single;
      expect(call.args.first, '1500');
      expect(call.args, containsAllInOrder(['--model', 'opus']));
      expect(
        call.args,
        containsAllInOrder([
          '--add-dir',
          fx.session.path,
          '--add-dir',
          fx.target.path,
        ]),
      );
      expect(fake.of('git').single.args, contains('get-url'));
    },
  );

  test('a real Opus error is reported as a synthesis failure', () async {
    fake.onRun = (_) => ok('not an envelope');
    final cfg = testConfig(fx.root);
    await expectLater(
      stage(cfg).run(fx.meta, frames),
      throwsA(
        isA<StateError>().having(
          (e) => '$e',
          'text',
          contains('synthesis failed: no JSON envelope'),
        ),
      ),
    );
  });
}
