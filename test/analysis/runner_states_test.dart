import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/job_lock.dart';
import 'package:game_research/analysis/runner.dart';
import 'package:game_research/core/usage.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

// Resilience (kuhy, 2026-11-12): the 23:10 shutdown left three jobs "running"
// forever. States are explicit, one job runs at a time, a usage limit on
// Opus waits instead of failing.
void main() {
  late Fixture fx;
  late FakeSys fake;
  var opusAnswer = ok(kAnswer);

  AnalysisRunner runner({int? ownerPid}) => AnalysisRunner(
    fx.session.path,
    testConfig(
      fx.root,
      extra: {
        'GAME_RESEARCH_FAKE_LLM': '/fake/llm',
        'GAME_RESEARCH_TODO_CMD': 'faketodo',
        'GAME_RESEARCH_STILL_S': '2',
      },
    ),
    fake.sys,
    MockClient((_) async => throw StateError('no network in tests')),
    ownerPid: ownerPid,
  );

  setUp(() {
    fx = Fixture();
    opusAnswer = ok(kAnswer);
    fake = FakeSys()
      ..onStart = ffmpegStart
      ..onRun = (c) {
        switch (c.exe) {
          case 'ffmpeg':
            return ffmpegFake(c);
          case '/fake/llm':
            return c.args.first == 'opus' ? opusAnswer : ok(kCaptionJson);
          case 'faketodo':
            return ok('task-1');
        }
        return bad('no remote', 2);
      };
  });

  JobLock lock() => JobLock(p.join(fx.root.path, 'data'));

  test(
    'a job live on another session queues: waiting, exit 4, no work',
    () async {
      final other = JobLock(p.join(fx.root.path, 'data'), selfPid: pid);
      expect(other.acquire('20261111-000000-other'), isTrue);
      expect(await runner(ownerPid: 123).run(), 4);
      expect(fx.status['state'], 'waiting');
      expect(fx.status['error'], contains('20261111-000000-other'));
      expect(fake.calls, isEmpty);
      other.release();
      expect(await runner().run(), 0);
      expect(fx.status['state'], 'done');
    },
  );

  test(
    'the same session already running is exit 3 and its status stays',
    () async {
      final held = JobLock(p.join(fx.root.path, 'data'), selfPid: pid);
      expect(held.acquire(p.basename(fx.session.path)), isTrue);
      expect(await runner().run(), 3);
      expect(fx.out('status.json').existsSync(), isFalse);
      held.release();
    },
  );

  test('the lock is held during the run and gone after', () async {
    var seen = '';
    fake.onRun = (c) {
      if (c.exe == 'ffmpeg') {
        seen = lock().holder()?.job ?? 'none';
        return ffmpegFake(c);
      }
      return c.exe == '/fake/llm'
          ? ok(c.args.first == 'opus' ? kAnswer : kCaptionJson)
          : ok('task-1');
    };
    await runner().run();
    expect(seen, p.basename(fx.session.path));
    expect(lock().holder(), isNull);
  });

  test(
    'an Opus usage limit waits: exit 4, retry time, captions kept',
    () async {
      opusAnswer = bad('Claude AI usage limit reached');
      expect(await runner().run(), 4);
      expect(fx.status['state'], 'waiting');
      expect(fx.status['stage'], 3);
      expect(fx.status['error'], contains('usage limit'));
      expect(
        fx.status['retry_unix']! as num,
        greaterThan(fake.now - 10),
        reason: 'retry time is in the future of the fake clock',
      );
      expect(lock().holder(), isNull);
      opusAnswer = ok(kAnswer);
      fake.calls.clear();
      expect(await runner().run(), 0);
      expect(fake.of('ffmpeg'), isEmpty, reason: 'stages 1-2 are done');
      expect(fx.status['state'], 'done');
    },
  );

  test('every tier rate limited waits instead of failing', () async {
    fake.onRun = (c) {
      if (c.exe == 'ffmpeg') return ffmpegFake(c);
      return bad('usage limit reached');
    };
    expect(await runner().run(), 4);
    expect(fx.status['state'], 'waiting');
    expect(fx.status['stage'], 2);
  });

  test('status carries start time, tokens and an eta while running', () async {
    final seen = <Map<String, Object?>>[];
    fake.onRun = (c) {
      if (fx.out('status.json').existsSync()) {
        seen.add(fx.status);
      }
      if (c.exe == 'ffmpeg') return ffmpegFake(c);
      return ok(c.args.first == 'opus' ? kAnswer : kCaptionJson);
    };
    await runner().run();
    expect(seen.every((s) => s['started_unix'] != null), isTrue);
    expect(fx.status['tokens'], isA<Map<String, Object?>>());
    expect(fx.status, containsPair('cost_usd', 0));
    expect(fx.status, contains('eta_s'));
  });

  test('tokens of captions and stage 3 add up in the status', () async {
    const spent = Usage(
      input: 10,
      output: 5,
      cacheRead: 1,
      cacheWrite: 2,
      costUsd: 0.1,
    );
    final row = jsonEncode({
      'frame': 'f_0001.png',
      't': 2,
      'tier': 'haiku',
      'model': 'm',
      'caption': {'screen': 's', 'action': 'a', 'prompt': ''},
      'skipped': <String>[],
      'usage': spent.toJson(),
    });
    fx.out('captions.jsonl')
      ..createSync(recursive: true)
      ..writeAsStringSync('$row\n');
    fx
        .out('stage3.json')
        .writeAsStringSync(
          jsonEncode({
            'tokens': {'in': 100, 'out': 50, 'cache_read': 0, 'cache_write': 0},
            'cost_usd': 0.9,
            'draft': 'x',
            'todo': 'y',
          }),
        );
    await runner().run();
    final tokens = fx.status['tokens']! as Map<String, Object?>;
    expect(tokens['in'], greaterThanOrEqualTo(110));
    expect(fx.status['cost_usd']! as num, closeTo(1.0, 1e-9));
  });
}
