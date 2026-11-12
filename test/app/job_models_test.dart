import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/job_models.dart';
import 'package:game_research/app/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_wrapper.dart';

void main() {
  group('JobStatus', () {
    test('an old session (no tokens, no eta) reads as zeros and nulls', () {
      final j = JobStatus.fromJson(const {
        'stage': 2,
        'done': 3,
        'total': 6,
        'state': 'running',
        'progress': 0.5,
      });
      expect(
        [j.stage, j.done, j.total, j.state, j.progress],
        [2, 3, 6, 'running', 0.5],
      );
      expect(j.tokens, isNull);
      expect(j.costUsd, isNull);
      expect(j.etaS, isNull);
      expect(JobStatus.fromJson(const {}).state, 'idle');
      expect(JobStatus.fromJson(null).progress, 0);
    });

    test('tokens total all four counters; cost and eta pass through', () {
      final j = JobStatus.fromJson(const {
        'state': 'done',
        'tokens': {'in': 1000, 'out': 200, 'cache_read': 30, 'cache_write': 4},
        'cost_usd': 0.4,
        'eta_s': 125,
      });
      expect(j.tokens?.total, 1234);
      expect(j.costUsd, 0.4);
      expect(j.etaS, 125);
      expect(j.etaMin, 3, reason: 'minutes left round up');
      expect(JobStatus.fromJson(const {'eta_s': 0}).etaMin, isNull);
    });

    test('active covers running and waiting only', () {
      for (final (s, active) in [
        ('running', true),
        ('waiting', true),
        ('interrupted', false),
        ('done', false),
        ('failed', false),
        ('idle', false),
      ]) {
        expect(JobStatus.fromJson({'state': s}).active, active, reason: s);
      }
    });
  });

  test('grouped writes digits with spaces, no letters', () {
    expect(grouped(0), '0');
    expect(grouped(999), '999');
    expect(grouped(1234), '1 234');
    expect(grouped(1234567), '1 234 567');
  });

  test('SessionRow reads the job, fps and keeps the old getters', () {
    final row = SessionRow.fromJson(const {
      'id': 's',
      'analysis': {'state': 'waiting', 'progress': 0.4, 'stage': 3},
      'fps': {'avg': 59.6, 'p1_low': 40, 'min': 20, 'samples': 9},
    });
    expect(row.state, 'waiting');
    expect(row.progress, 0.4);
    expect(row.job.stage, 3);
    expect(row.fpsAvg, 59.6);
    expect(SessionRow.fromJson(const {'id': 'x'}).fpsAvg, isNull);
  });

  test('Game reads slug and finish; no finish means none', () {
    final g = Game.fromJson(const {
      'appid': 1,
      'name': 'One',
      'slug': 'one',
      'finish': {
        'state': 'done',
        'progress': 1,
        'report': '/r.md',
        'merged': '/m.md',
      },
    });
    expect(g.slug, 'one');
    expect(g.finish?.state, 'done');
    expect(g.finish?.report, '/r.md');
    expect(Game.fromJson(const {'appid': 2}).finish, isNull);
  });

  group('ResearchApi', () {
    test(
      'a page opened with ?autostart=1 does not leak it into calls',
      () async {
        final calls = <String>[];
        final api = ResearchApi(
          Uri.parse('http://127.0.0.1:8805/?autostart=1'),
          MockClient((r) async {
            calls.add('${r.method} ${r.url}');
            return http.Response('{}', 200);
          }),
        );
        await api.stop();
        await api.analyze('s1');
        await api.finish(4);
        expect(calls, [
          'POST http://127.0.0.1:8805/api/stop',
          'POST http://127.0.0.1:8805/api/sessions/s1/analyze',
          'POST http://127.0.0.1:8805/api/games/4/finish',
        ]);
        expect(api.capsuleUrl(3), 'http://127.0.0.1:8805/api/capsule/3');
      },
    );

    test('doc reads and saves through /api/doc', () async {
      final w = FakeWrapper()..docs['/t/a.md'] = '# a';
      final api = w.api();
      expect(await api.doc('/t/a.md'), '# a');
      await api.saveDoc('/t/a.md', '# b');
      expect(w.docs['/t/a.md'], '# b');
      expect(w.calls, [
        'GET /api/doc?path=%2Ft%2Fa.md',
        'PUT /api/doc?path=%2Ft%2Fa.md # b',
      ]);
      await expectLater(api.doc('/nope.md'), throwsA(isA<ApiError>()));
    });
  });
}
