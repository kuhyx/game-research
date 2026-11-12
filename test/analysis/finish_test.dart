import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/finish.dart';
import 'package:game_research/analysis/job_lock.dart';
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
  var llm = ok(_answer);

  FinishRunner runner({int? ownerPid}) => FinishRunner(
    'alpha',
    testConfig(
      fx.root,
      extra: {
        'GAME_RESEARCH_FAKE_LLM': '/fake/llm',
        'GAME_RESEARCH_TODO_CMD': 'faketodo',
      },
    ),
    fake.sys,
    ownerPid: ownerPid,
    recordingPoll: const Duration(milliseconds: 5),
  );

  /// Marks the fixture session analysed: its draft exists and stage3 says so.
  String analysed(Directory session, {String stamp = '20261112-090025'}) {
    final draft = draftPath(fx.target.path, 'alpha', stamp);
    File(draft)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(kDraft);
    File(p.join(session.path, 'analysis', 'stage3.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'draft': draft, 'todo': 't'}));
    return draft;
  }

  Map<String, Object?> json(String name) =>
      jsonDecode(File(p.join(data, 'games', 'alpha', name)).readAsStringSync())
          as Map<String, Object?>;

  setUp(() {
    fx = Fixture();
    data = p.join(fx.root.path, 'data');
    llm = ok(_answer);
    fake = FakeSys()
      ..onRun = (c) {
        switch (c.exe) {
          case '/fake/llm':
            return llm;
          case 'faketodo':
            return ok('task-9\n');
        }
        return ok('git@github.com:kuhyx/cleanup-plate.git\n');
      };
  });

  test('merges every draft, writes merged + report, one todo, done', () async {
    analysed(fx.session);
    final second = Directory(p.join(data, '20261113-100000-alpha'))
      ..createSync(recursive: true);
    File(p.join(second.path, 'session.json'))
        .writeAsStringSync(jsonEncode({...fx.meta, 'game': 'Alpha'}));
    analysed(second, stamp: '20261113-100000');
    expect(await runner().run(), 0);
    expect(
      File(mergedPath(fx.target.path, 'alpha')).readAsStringSync(),
      kDraft,
    );
    expect(
      File(reportPath(fx.target.path, 'alpha')).readAsStringSync(),
      _report,
    );
    final prompt = File(p.join(data, 'games', 'alpha', 'finish_prompt.txt'))
        .readAsStringSync();
    expect(prompt, contains('DOCS-research-alpha-20261112-090025.md'));
    expect(prompt, contains('DOCS-research-alpha-20261113-100000.md'));
    expect(prompt, contains('2 play session'));
    final done = json('finish.json');
    expect(done['state'], 'done');
    expect(done['sessions'], ['20261112-090025', '20261113-100000']);
    expect(done['report'], reportPath(fx.target.path, 'alpha'));
    expect(done['merged'], mergedPath(fx.target.path, 'alpha'));
    expect(done['todo'], 'task-9');
    expect(done['finished_unix'], isA<num>());
    expect(done['model'], 'fake:opus');
    expect(done, contains('tokens'));
    expect(json('status.json')['state'], 'done');
    final todo = fake.of('faketodo').single;
    expect(
      todo.args.last,
      startsWith('Apply Alpha research to cleanup-plate\n'),
    );
    expect(todo.args.last, isNot(contains('MANUAL WORK REQUIRED')));
    expect(todo.args.last, contains('Copy the tidy-up loop.'));
    expect(todo.args.last, contains(reportPath(fx.target.path, 'alpha')));
    expect(todo.args.last, contains(mergedPath(fx.target.path, 'alpha')));
    expect(todo.args, containsAllInOrder(['--repo', 'kuhyx/cleanup-plate']));
    expect(todo.args, containsAllInOrder(['--done-check', 'make test']));
    expect(done['done_check'], 'make test');
    expect(JobLock(data).holder(), isNull);
  });

  test('the real Opus call reads the target and every session', () async {
    analysed(fx.session);
    final env = jsonEncode({
      'subtype': 'success',
      'is_error': false,
      'result': _answer,
      'modelUsage': {'claude-opus-4-8': <String, Object>{}},
      'usage': {'input_tokens': 70, 'output_tokens': 30},
      'total_cost_usd': 0.75,
    });
    fake.onRun = (c) => switch (c.exe) {
      'timeout' => ok(env),
      'faketodo' => ok('t-3'),
      _ => ok('git@github.com:kuhyx/cleanup-plate.git\n'),
    };
    final real = FinishRunner(
      'alpha',
      testConfig(fx.root, extra: {'GAME_RESEARCH_TODO_CMD': 'faketodo'}),
      fake.sys,
    );
    expect(await real.run(), 0);
    final call = fake.of('timeout').single;
    expect(call.args, containsAllInOrder(['--model', 'opus']));
    expect(
      call.args,
      containsAllInOrder([
        '--add-dir',
        fx.target.path,
        '--add-dir',
        fx.session.path,
      ]),
    );
    final done = json('finish.json');
    expect(done['model'], 'claude-opus-4-8');
    expect(done['tokens'], containsPair('in', 70));
    expect(done['cost_usd'], 0.75);
  });

  test('a rerun with nothing new costs nothing', () async {
    analysed(fx.session);
    await runner().run();
    final calls = fake.calls.length;
    expect(await runner().run(), 0);
    expect(fake.calls, hasLength(calls));
    expect(json('status.json')['state'], 'done');
  });

  test('a new session merges again and keeps the spend', () async {
    analysed(fx.session);
    await runner().run();
    final first = json('finish.json');
    final second = Directory(p.join(data, '20261113-100000-alpha'))
      ..createSync(recursive: true);
    File(p.join(second.path, 'session.json'))
        .writeAsStringSync(jsonEncode(fx.meta));
    analysed(second, stamp: '20261113-100000');
    expect(await runner().run(), 0);
    expect(fake.of('/fake/llm'), hasLength(2));
    expect(json('finish.json')['sessions'], hasLength(2));
    expect(json('finish.json')['tokens'], first['tokens']);
  });

  test('no analysed session fails closed', () async {
    Directory(p.join(fx.session.path, 'analysis')).createSync();
    fx.out('status.json').writeAsStringSync('{"state":"failed"}');
    expect(await runner().run(), 1);
    expect(json('status.json')['state'], 'failed');
    expect(json('status.json')['error'], contains('no analysed session'));
  });

  test('a session without a draft file is not merged', () async {
    final draft = analysed(fx.session);
    File(draft).deleteSync();
    expect(analysedSessions(data, 'alpha'), isEmpty);
  });

  test('a missing template, or a bad answer, writes nothing', () async {
    analysed(fx.session);
    File(templatePath(fx.target.path)).deleteSync();
    expect(await runner().run(), 1);
    expect(json('status.json')['error'], contains('no questions template'));
    File(templatePath(fx.target.path)).writeAsStringSync(kTemplate);
    llm = ok('@@@MERGED\n# x\n@@@REPORT\n# y\n@@@TASK\nt\n@@@CHECK\nc\n@@@END');
    expect(await runner().run(), 1);
    expect(File(mergedPath(fx.target.path, 'alpha')).existsSync(), isFalse);
    llm = bad('boom', 4);
    expect(await runner().run(), 1);
    expect(json('status.json')['error'], contains('finish failed'));
  });

  test('a usage limit on Opus waits and the retry finishes', () async {
    analysed(fx.session);
    llm = bad('Claude AI usage limit reached');
    expect(await runner().run(), 4);
    expect(json('status.json')['state'], 'waiting');
    expect(json('status.json')['retry_unix'], isA<num>());
    llm = ok(_answer);
    expect(await runner().run(), 0);
    expect(json('finish.json')['state'], 'done');
  });

  test('another job holds the machine: queued, exit 4', () async {
    analysed(fx.session);
    final other = JobLock(data)..acquire('20261111-000000-other');
    expect(await runner(ownerPid: 123).run(), 4);
    expect(json('status.json')['state'], 'waiting');
    other.release();
  });

  test('a recording in progress holds the job until it ends', () async {
    analysed(fx.session);
    final flag = File(p.join(data, 'recording.pid'))..writeAsStringSync('$pid');
    var finished = false;
    final job = runner().run().then((c) {
      finished = true;
      return c;
    });
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(finished, isFalse);
    expect(fake.calls, isEmpty);
    flag.deleteSync();
    expect(await job, 0);
  });
}
