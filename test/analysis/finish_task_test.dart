import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/finish.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

// kuhy, 2026-11-12: the finished game's report becomes ONE todoImplementer
// task (not a manual review); no repo slug or a bad Opus section fails closed.
void main() {
  late Fixture fx;
  late FakeSys fake;
  late String data;
  var answer = finishAnswer();
  var remote = ok('git@github.com:kuhyx/cleanup-plate.git\n');

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

  Map<String, Object?> json(String name) =>
      jsonDecode(File(p.join(data, 'games', 'alpha', name)).readAsStringSync())
          as Map<String, Object?>;

  setUp(() {
    fx = Fixture();
    data = p.join(fx.root.path, 'data');
    answer = finishAnswer();
    remote = ok('git@github.com:kuhyx/cleanup-plate.git\n');
    final draft = draftPath(fx.target.path, 'alpha', '20261112-090025');
    File(draft)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(kDraft);
    Directory(p.join(fx.session.path, 'analysis')).createSync();
    File(p.join(fx.session.path, 'analysis', 'stage3.json'))
        .writeAsStringSync(jsonEncode({'draft': draft, 'todo': 't'}));
    fake = FakeSys()
      ..onRun = (c) => switch (c.exe) {
        '/fake/llm' => ok(answer),
        'faketodo' => ok('task-7\n'),
        'git' => remote,
        _ => bad('x', 2),
      };
  });

  test('one task, stored with its id and done check', () async {
    expect(await runner().run(), 0);
    expect(fake.of('faketodo'), hasLength(1));
    expect(json('finish.json'), containsPair('todo', 'task-7'));
    expect(json('finish.json'), containsPair('done_check', 'make test'));
    expect(json('finish.json'), contains('task'));
  });

  test('no derivable repo slug: failed before any Opus call', () async {
    remote = bad('fatal: no such remote', 128);
    expect(await runner().run(), 1);
    expect(json('status.json')['error'], contains('repo slug'));
    expect(fake.of('/fake/llm'), isEmpty);
    expect(fake.of('faketodo'), isEmpty);
  });

  test('a malformed task or check writes nothing and makes no task', () async {
    for (final bad in [
      finishAnswer(check: 'a\nb'),
      finishAnswer(task: ' '),
      '@@@MERGED\n$kDraft@@@REPORT\n# R\nok\n@@@END\n',
    ]) {
      answer = bad;
      expect(await runner().run(), 1, reason: bad);
      expect(File(mergedPath(fx.target.path, 'alpha')).existsSync(), isFalse);
    }
    expect(fake.of('faketodo'), isEmpty);
  });

  test('a failed todo call retries without a second Opus call', () async {
    fake.onRun = (c) => switch (c.exe) {
      '/fake/llm' => ok(answer),
      'git' => remote,
      _ => bad('locked', 5),
    };
    expect(await runner().run(), 1);
    fake.onRun = (c) => c.exe == 'faketodo' ? ok('t-2') : remote;
    expect(await runner().run(), 0);
    expect(fake.of('/fake/llm'), hasLength(1));
    expect(fake.of('faketodo').last.args, contains('make test'));
    expect(json('finish.json'), containsPair('todo', 't-2'));
  });
}
