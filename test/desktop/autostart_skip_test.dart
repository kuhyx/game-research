import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/session_flow.dart';
import 'package:path/path.dart' as p;

import '../support/server_harness.dart';

// kuhy, 2026-11-12: "When I open playstudy it still tries to autostart a
// game even though all games have been flagged as finished."
const slug = 'librarian-tidy-up-the-arcane-library';

void main() {
  late ServerHarness s;

  void finishRequested([String state = 'queued']) =>
      File(p.join(s.h.config.dataDir, 'games', slug, 'finish.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'state': state}));

  Map<String, Object?> skip() => s.h.log
      .tail(1000)
      .map((l) => jsonDecode(l) as Map<String, Object?>)
      .lastWhere((e) => e['event'] == 'autostart_skip');

  setUp(() async {
    s = await ServerHarness.start(
      games: {4197610: 'Librarian: Tidy Up the Arcane Library!', 5: 'Other'},
    );
    s.h.parts.targets.settings.merge({'last_appid': 4197610});
  });

  for (final state in ['queued', 'waiting', 'running', 'done', 'failed']) {
    test('a $state finish: autostart arms nothing and says why', () async {
      finishRequested(state);
      final r = await s.hit('POST', '/api/autostart');
      expect(r.status, 200, reason: 'not an error: nothing was due');
      expect((r.json! as Map)['phase'], 'idle');
      expect(s.server.flow.phase, Phase.idle);
      expect(s.h.events, isNot(contains('autostart_arm')));
      expect(skip(), containsPair('appid', 4197610));
      expect(skip(), containsPair('reason', 'finished'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(s.h.fake.of('systemd-run'), isEmpty);
    });
  }

  test(
    'an unfinished game still autostarts; a pending ring is a 409',
    () async {
      finishRequested();
      expect((await s.hit('POST', '/api/autostart?appid=5')).status, 200);
      expect(s.server.flow.phase, Phase.armed);
      expect(s.h.events, contains('autostart_arm'));
      expect((await s.hit('POST', '/api/autostart')).status, 409);
      s.server.flow.cancel('test');
    },
  );

  test('no finish requested: the last game arms as before', () async {
    expect((await s.hit('POST', '/api/autostart')).status, 200);
    expect(s.server.flow.phase, Phase.armed);
    s.server.flow.cancel('test');
  });

  test('the picker still starts a finished game by hand', () async {
    finishRequested('done');
    final r = await s.hit('POST', '/api/start?appid=4197610');
    expect(r.status, 200);
    expect(s.h.fake.of('systemd-run'), hasLength(1));
    s.server.flow.cancel('test');
  });
}
