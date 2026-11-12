import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/steam.dart';
import 'package:game_research/desktop/session_flow.dart';
import 'package:game_research/desktop/steam_library.dart';
import 'package:path/path.dart' as p;

import '../support/session_harness.dart';

const game = SteamGame(appid: 4197610, name: 'Librarian');

void main() {
  late Harness h;

  setUp(() {
    h = Harness();
    h.fake.step = 0; // the session window is exactly [now, now]
  });

  Directory session() => Directory(h.config.dataDir)
      .listSync()
      .whereType<Directory>()
      .singleWhere((d) => File(p.join(d.path, 'session.json')).existsSync());

  Map<String, Object?> meta() => jsonDecode(
    File(p.join(session().path, 'session.json')).readAsStringSync(),
  ) as Map<String, Object?>;

  test('stop moves the game log into fps/ and records the figures', () async {
    File(p.join(h.config.dataDir, 'fps-spool', 'Librarian.csv'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        File('test/fixtures/mangohud_0.8.csv').readAsStringSync(),
      )
      ..setLastModifiedSync(DateTime.fromMillisecondsSinceEpoch(1700000005000));
    await h.controller.start(game);
    h.fake.now = 1700000010; // the session ends 10 s after it began
    await h.controller.stop();
    expect(meta()['fps'], {
      'avg': 95.2,
      'p1_low': 50.0,
      'min': 20.0,
      'samples': 100,
    });
    expect(
      File(p.join(session().path, 'fps', 'Librarian.csv')).existsSync(),
      true,
    );
    expect(h.events, contains('fps'));
  });

  test('a session without a log has fps: null', () async {
    await h.controller.start(game);
    await h.controller.stop();
    expect(meta().containsKey('fps'), true);
    expect(meta()['fps'], isNull);
  });

  test('SessionFlow prepares the launch option before Steam starts', () async {
    final apps = Directory(p.join(h.config.steamRoot, 'steamapps'))
      ..createSync(recursive: true);
    File('test/fixtures/appmanifest_4197610.acf')
        .copySync(p.join(apps.path, 'appmanifest_4197610.acf'));
    final flow = SessionFlow(
      h.controller,
      SteamLibrary(h.config.steamRoot),
      every: const Duration(milliseconds: 10),
    );
    await flow.start(4197610);
    flow.cancel('test');
    expect(h.events, containsAllInOrder(['fps_launch_option', 'launch']));
  });
}
