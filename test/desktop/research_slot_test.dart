import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/research_game.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/research_slot.dart';
import 'package:path/path.dart' as p;

import '../support/fake_enforcer.dart';
import '../support/fakes.dart';

void main() {
  late Directory root;
  late FakeEnforcer enforcer;
  late ResearchSlot slot;

  setUp(() async {
    root = tempDir();
    enforcer = await FakeEnforcer.start(root);
    slot = ResearchSlot(
      testConfig(root, extra: {'GAME_RESEARCH_ENFORCER_SOCK': enforcer.path}),
    );
  });

  test('defaults: approval file under ~/.config/game-research', () {
    final env = {'HOME': root.path, 'GAME_RESEARCH_DATA': '${root.path}/d'};
    expect(
      ResearchSlot(Config.fromEnv(env, cwd: root.path)).file.path,
      p.join(root.path, '.config', 'game-research', 'research_game.json'),
    );
  });

  test("test mode never defaults to kuhy's approval file", () {
    // An E2E add with the real HOME would overwrite, then delete on the
    // missing socket, kuhy's live research game.
    expect(slot.file.path, p.join(root.path, 'data', 'research_game.json'));
  });

  test('test mode has no enforcer socket unless one is given', () async {
    final bare = ResearchSlot(testConfig(root));
    expect(await bare.add(7), ResearchAdd.refused);
    expect(bare.file.existsSync(), isFalse);
  });

  test('add writes the file with the session flags, then registers', () async {
    expect(await slot.add(7), ResearchAdd.added);
    final a = ResearchApproval.parse(slot.file.readAsStringSync())!;
    expect(a.appid, 7);
    expect(a.flags, [
      p.join(root.path, 'data', 'recording.pid'),
      p.join(root.path, 'data', 'research_launch.pid'),
    ]);
    expect(enforcer.requests.single, {
      'op': 'research_game',
      'args': {'app_id': 7},
    });
    expect(slot.appid, 7);
  });

  test('a second game is refused while the slot is taken', () async {
    await slot.add(7);
    expect(await slot.add(8), ResearchAdd.taken);
    expect(slot.appid, 7);
    expect(enforcer.ops, ['research_game']);
  });

  test('the enforcer refusing rolls the file back', () async {
    enforcer.refuse.add('research_game');
    expect(await slot.add(7), ResearchAdd.refused);
    expect(slot.file.existsSync(), isFalse);
  });

  test('remove deletes the file and revokes', () async {
    await slot.add(7);
    expect(await slot.remove(), 7);
    expect(slot.file.existsSync(), isFalse);
    expect(enforcer.ops.last, 'research_game_revoke');
    expect(await slot.remove(), isNull);
  });

  test('owned and allowed come from the enforcer config dir', () {
    final dir = Directory(
      p.join(root.path, '.config', 'steam_backlog_enforcer'),
    )..createSync(recursive: true);
    File(p.join(dir.path, 'owned_app_ids_cache.json')).writeAsStringSync(
      jsonEncode({
        'games': [
          {'app_id': 3, 'name': 'C'},
        ],
      }),
    );
    File(p.join(dir.path, 'state.json'))
        .writeAsStringSync(jsonEncode({'current_app_id': 3}));
    expect(slot.owned(), {3: 'C'});
    expect(slot.allowed(), {3});
  });

  test('the launch flag goes up and down', () {
    slot.launchFlag.raise();
    expect(
      File(p.join(root.path, 'data', 'research_launch.pid')).readAsStringSync(),
      '$pid',
    );
    slot.launchFlag.lower();
    expect(slot.launchFlag.file.existsSync(), isFalse);
  });
}
