import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_wrapper.dart';

void main() {
  test('reads state, games, targets and sessions', () async {
    final w = FakeWrapper()
      ..recording = true
      ..sessions = [
        {
          'id': 's1',
          'appid': 1,
          'game': 'One',
          'started_unix': 5,
          'duration_s': 61,
          'markers': {'good': 1},
          'analysis': {'progress': 0.5, 'state': 'running'},
          'draft': '/d.md',
        },
      ];
    final api = w.api();
    final s = await api.state();
    expect(s.recording, isTrue);
    expect(s.appid, 1);
    expect(s.counts['good'], 2);
    expect((await api.games()).last.capsule, isFalse);
    expect((await api.targets()).paths, hasLength(2));
    final row = (await api.sessions()).single;
    expect(row.progress, 0.5);
    expect(row.draft, '/d.md');
    expect(api.capsuleUrl(3), 'http://127.0.0.1:1/api/capsule/3');
  });

  test('posts start, stop, markers, notes, target, analyze, finish', () async {
    final w = FakeWrapper();
    final api = w.api();
    await api.start(4);
    expect(await api.marker('note', hold: true), 7);
    expect(await api.marker('good'), isNull);
    await api.note(7, 'hi');
    await api.pickTarget('/src/other');
    await api.analyze('s1');
    await api.finish(4);
    await api.stop();
    expect(w.calls, [
      'POST /api/start?appid=4',
      'POST /api/marker?tag=note&src=gui&hold=1',
      'POST /api/marker?tag=good&src=gui',
      'POST /api/note?id=7 hi',
      'POST /api/target /src/other',
      'POST /api/sessions/s1/analyze',
      'POST /api/games/4/finish',
      'POST /api/stop',
    ]);
  });

  test('a non-2xx answer is an ApiError with the reason', () async {
    final w = FakeWrapper()..postStatus = 409;
    await expectLater(
      w.api().start(1),
      throwsA(
        isA<ApiError>()
            .having((e) => e.status, 'status', 409)
            .having((e) => '$e', 'text', contains('nope')),
      ),
    );
    final down = FakeWrapper()..getStatus = 500;
    await expectLater(down.api().games(), throwsA(isA<ApiError>()));
  });

  test('an empty or non-object POST answer reads as no fields', () async {
    final api = ResearchApi(
      Uri.parse('http://127.0.0.1:1/'),
      MockClient(
        (r) async => http.Response(r.url.path == '/api/stop' ? '' : '[1]', 200),
      ),
    );
    await api.stop();
    expect(await api.marker('good'), isNull);
  });

  test('models fall back to defaults on missing fields', () {
    final s = AppState.fromJson(const {});
    expect(s.recording, isFalse);
    expect(s.appid, isNull);
    expect(s.counts, isEmpty);
    expect(TargetList.fromJson(const {}).paths, isEmpty);
    final row = SessionRow.fromJson(const {'id': 'x'});
    expect(row.state, 'idle');
    expect(row.draft, isNull);
    expect(Game.fromJson(const {}).name, '');
  });

  test('clock is mm:ss under an hour, h:mm:ss from an hour on', () {
    expect(clock(-3), '00:00');
    expect(clock(61.9), '01:01');
    expect(clock(3725), '1:02:05');
  });
}
