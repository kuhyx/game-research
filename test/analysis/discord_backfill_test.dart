import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/cli.dart';
import 'package:game_research/analysis/job_lock.dart';
import 'package:game_research/core/discord_doc.dart';
import 'package:game_research/desktop/recording_flag.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

void main() {
  late Fixture fx;
  late FakeSys fake;
  late String data;
  late File errFile;
  late RecordingFlag flag;
  var reply = (Call c) => ok(kDiscordAnswer);

  Future<int> run([List<String> args = const ['--discord-backfill']]) async {
    final sink = errFile.openWrite();
    final code = await analyzeMain(
      args,
      testConfig(fx.root, extra: {'GAME_RESEARCH_FAKE_LLM': '/fake/llm'}),
      fake.sys,
      MockClient((_) async => throw StateError('no network in tests')),
      recordingPoll: const Duration(milliseconds: 5),
      err: sink,
    );
    await sink.close();
    return code;
  }

  /// A session folder under data/ whose stage3.json names [draft].
  String session(String name, String draft, {String key = 'draft'}) {
    final dir = Directory(p.join(data, name))..createSync(recursive: true);
    File(p.join(dir.path, 'session.json')).writeAsStringSync('{}');
    File(p.join(dir.path, 'analysis', 'stage3.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({key: draft, 'todo': 't'}));
    return dir.path;
  }

  String doc(String name) =>
      (File(p.join(fx.target.path, 'docs', 'research', name))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('# Long\n'))
          .path;

  String report(String slug) {
    final path = doc('DOCS-research-$slug-report.md');
    File(p.join(data, 'games', slug, 'finish.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'report': path, 'state': 'done'}));
    return path;
  }

  Map<String, Object?> state(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

  bool hasShort(String docPath) => File(discordPathOf(docPath)).existsSync();

  List<Call> llm() => fake.of('/fake/llm');

  setUp(() {
    fx = Fixture();
    data = p.join(fx.root.path, 'data');
    errFile = File(p.join(fx.root.path, 'err.txt'))..createSync();
    flag = RecordingFlag(data);
    // The queue drain afterwards finds nothing to analyse.
    File(p.join(fx.session.path, 'recording.mkv')).deleteSync();
    reply = (c) => ok(kDiscordAnswer);
    fake = FakeSys()..onRun = (c) => c.exe == '/fake/llm' ? reply(c) : null;
  });

  test(
    'writes the short version of every draft and report without one',
    () async {
      final d1 = doc('DOCS-research-alpha-20261112-090025.md');
      final d2 = doc('DOCS-research-alpha-20261113-100000.md');
      final s1 = session('20261112-090025-alpha', d1);
      session('20261113-100000-alpha', d2);
      final r = report('alpha');
      expect(await run(), 0);
      for (final path in [d1, d2, r]) {
        expect(
          File(discordPathOf(path)).readAsStringSync(),
          contains('# Short'),
        );
        expect(File(path).readAsStringSync(), '# Long\n');
      }
      expect(llm(), hasLength(3));
      expect(state(p.join(s1, 'analysis', 'stage3.json')), {
        'draft': d1,
        'todo': 't',
        'discord': 'ok',
      });
      expect(state(p.join(data, 'games', 'alpha', 'finish.json')), {
        'report': r,
        'state': 'done',
        'report_discord': 'ok',
      });
      final status = state(p.join(data, 'discord_backfill.json'));
      expect(status, containsPair('state', 'done'));
      expect(JobLock(data).holder(), isNull);
    },
  );

  test('an existing short version is skipped, not rewritten', () async {
    final d1 = doc('DOCS-research-alpha-20261112-090025.md');
    session('20261112-090025-alpha', d1);
    File(discordPathOf(d1)).writeAsStringSync('mine\n');
    expect(await run(), 0);
    expect(llm(), isEmpty);
    expect(File(discordPathOf(d1)).readAsStringSync(), 'mine\n');
  });

  test('nothing to do: no call, exit 0', () async {
    expect(await run(), 0);
    expect(fake.calls, isEmpty);
  });

  test(
    'a v1 draft shared by sessions, or a missing draft, costs no extra call',
    () async {
      final shared = doc('DOCS-research-alpha.md');
      session('20261112-090025-alpha', shared, key: 'draft_en');
      session('20261113-100000-alpha', shared, key: 'draft_en');
      session('20261114-100000-alpha', p.join(fx.root.path, 'gone.md'));
      expect(await run(), 0);
      expect(llm(), hasLength(1));
      expect(hasShort(shared), isTrue);
    },
  );

  test('a failing doc is reported and the run goes on; exit 1', () async {
    final d1 = doc('DOCS-research-alpha-20261112-090025.md');
    final d2 = doc('DOCS-research-alpha-20261113-100000.md');
    final s1 = session('20261112-090025-alpha', d1);
    session('20261113-100000-alpha', d2);
    reply = (c) => File(c.args[1]).readAsStringSync().contains(d1)
        ? ok('| table |')
        : ok(kDiscordAnswer);
    expect(await run(), 1);
    expect(hasShort(d1), isFalse);
    expect(hasShort(d2), isTrue);
    expect(errFile.readAsStringSync(), contains(d1));
    expect(
      state(p.join(s1, 'analysis', 'stage3.json'))['discord'],
      startsWith('failed: '),
    );
  });

  test('a usage limit stops the run with exit 4', () async {
    final d1 = doc('DOCS-research-alpha-20261112-090025.md');
    final d2 = doc('DOCS-research-alpha-20261113-100000.md');
    session('20261112-090025-alpha', d1);
    session('20261113-100000-alpha', d2);
    reply = (c) => bad('Claude AI usage limit reached');
    expect(await run(), 4);
    expect(llm(), hasLength(1), reason: 'stopped at the first');
    expect(hasShort(d1) || hasShort(d2), isFalse);
    expect(
      state(p.join(data, 'discord_backfill.json')),
      containsPair('state', 'waiting'),
    );
    expect(JobLock(data).holder(), isNull);
  });

  test('it waits while a recording runs', () async {
    final d1 = doc('DOCS-research-alpha-20261112-090025.md');
    session('20261112-090025-alpha', d1);
    flag.raise();
    final job = run();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(fake.calls, isEmpty);
    flag.lower();
    expect(await job, 0);
    expect(hasShort(d1), isTrue);
  });

  test('a busy machine queues it (exit 4) without a call', () async {
    session(
      '20261112-090025-alpha',
      doc('DOCS-research-alpha-20261112-090025.md'),
    );
    final other = JobLock(data, selfPid: pid)..acquire('someone-else');
    expect(await run(), 4);
    expect(fake.calls, isEmpty);
    other.release();
  });

  test('extra arguments print the usage and exit 2', () async {
    expect(await run(['--discord-backfill', 'x']), 2);
    expect(await run(['--discord-backfill', '--force']), 2);
    expect(errFile.readAsStringSync(), contains('--discord-backfill'));
  });
}
