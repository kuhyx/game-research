import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fake_enforcer.dart';
import '../support/fakes.dart';
import '../support/server_harness.dart';

const librarian = 4197610;
const other = 570;

void main() {
  late ServerHarness s;
  late FakeEnforcer enforcer;

  File approval() => File(p.join(s.h.config.dataDir, 'research_game.json'));

  setUp(() async {
    final sockDir = tempDir();
    enforcer = await FakeEnforcer.start(sockDir);
    s = await ServerHarness.start(
      games: {730: 'Alpha'},
      env: {'GAME_RESEARCH_ENFORCER_SOCK': enforcer.path},
    );
    final dir = Directory(
      p.join(s.h.root.path, '.config', 'steam_backlog_enforcer'),
    )..createSync(recursive: true);
    File(p.join(dir.path, 'owned_app_ids_cache.json')).writeAsStringSync(
      jsonEncode({
        'games': [
          {'app_id': 730, 'name': 'Alpha'},
          {'app_id': other, 'name': 'Dota'},
          {'app_id': librarian, 'name': 'Librarian'},
        ],
      }),
    );
  });

  Future<Map<int, Map<String, Object?>>> games() async {
    final list = (await s.hit('GET', '/api/games')).json! as List;
    return {
      for (final g in list.cast<Map<String, Object?>>()) g['appid']! as int: g,
    };
  }

  test('every owned game is listed; blocked ones carry the lock', () async {
    final g = await games();
    expect(g.keys, [730, other, librarian]);
    expect(g[730]!['lock'], 'open');
    expect(g[other]!['lock'], 'blocked');
    expect(g[other]!['state'], 'absent');
    expect(g[librarian]!['name'], 'Librarian');
  });

  test('adding approves at once, registers and starts the install', () async {
    final r = await s.hit('POST', '/api/research?appid=$librarian');
    expect(r.status, 200);
    expect(enforcer.ops, ['research_game']);
    expect(
      (jsonDecode(approval().readAsStringSync()) as Map)['app_id'],
      librarian,
    );
    final run = s.h.fake.of('systemd-run').single;
    expect(run.args.last, 'steam://install/$librarian');
    final g = await games();
    expect(g[librarian]!['lock'], 'research');
    expect(g[other]!['lock'], 'taken');
    expect(s.h.events, contains('research_add'));
  });

  test('a second game is refused while the slot is taken', () async {
    await s.hit('POST', '/api/research?appid=$librarian');
    final r = await s.hit('POST', '/api/research?appid=$other');
    expect(r.status, 409);
    expect(
      (jsonDecode(approval().readAsStringSync()) as Map)['app_id'],
      librarian,
    );
  });

  test('an enforcer refusal is a 502 and approves nothing', () async {
    enforcer.refuse.add('research_game');
    final r = await s.hit('POST', '/api/research?appid=$librarian');
    expect(r.status, 502);
    expect(approval().existsSync(), isFalse);
    expect(s.h.fake.of('systemd-run'), isEmpty);
  });

  test('an unknown game is a 404', () async {
    expect((await s.hit('POST', '/api/research?appid=1')).status, 404);
  });

  test('remove revokes and deletes nothing in the data dir', () async {
    final note = File(p.join(s.h.config.dataDir, 'keep.txt'))
      ..createSync(recursive: true);
    await s.hit('POST', '/api/research?appid=$librarian');
    final r = await s.hit('POST', '/api/research/remove');
    expect(r.status, 200);
    expect(approval().existsSync(), isFalse);
    expect(enforcer.ops.last, 'research_game_revoke');
    expect(note.existsSync(), isTrue);
    expect((await games())[other]!['lock'], 'blocked');
  });
}
