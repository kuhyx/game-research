import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/steam_vdf.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/fps_session.dart';
import 'package:game_research/desktop/launcher.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const vdf = '''
"UserLocalConfigStore"
{
\t"Software"
\t{
\t\t"Valve"
\t\t{
\t\t\t"Steam"
\t\t\t{
\t\t\t\t"apps"
\t\t\t\t{
\t\t\t\t\t"20"
\t\t\t\t\t{
\t\t\t\t\t\t"LaunchOptions"\t\t"mangohud %command%"
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}
\t\t}
\t}
}
''';

void main() {
  late Directory root;

  Config configWith(Map<String, String> extra) => testConfig(
    root,
    extra: {
      'GAME_RESEARCH_REPO': Directory.current.path,
      'GAME_RESEARCH_PROC': p.join(root.path, 'proc'),
      'GAME_RESEARCH_STEAM_PID': p.join(root.path, 'steam.pid'),
      ...extra,
    },
  );

  File localconfig(Config c) =>
      File(p.join(c.steamRoot, 'userdata', '111', 'config', 'localconfig.vdf'));

  void manifest(String steamapps, int id, String name) {
    Directory(steamapps).createSync(recursive: true);
    File(p.join(steamapps, 'appmanifest_$id.acf')).writeAsStringSync(
      '"AppState"\n{\n\t"appid"\t\t"$id"\n\t"name"\t\t"$name"\n'
      '\t"StateFlags"\t\t"4"\n}\n',
    );
  }

  /// A Steam root with games 10 and 20, game 30 in a second library, a
  /// Proton tool (40) and one account whose game 20 runs kuhy's MangoHud.
  void stage(Config c) {
    final apps = p.join(c.steamRoot, 'steamapps');
    final second = p.join(root.path, 'lib2');
    manifest(apps, 10, 'Alpha');
    manifest(apps, 20, 'Beta');
    manifest(apps, 40, 'Proton 9.0');
    manifest(p.join(second, 'steamapps'), 30, 'Gamma');
    File(p.join(apps, 'libraryfolders.vdf')).writeAsStringSync(
      '"libraryfolders"\n{\n"0" { "path" "${c.steamRoot}" }\n'
      '"1" { "path" "$second" }\n}\n',
    );
    localconfig(c)
      ..createSync(recursive: true)
      ..writeAsStringSync(vdf);
    Directory(c.procRoot).createSync(recursive: true);
  }

  List<Map<String, Object?>> events(Config c) => [
    for (final l in EventLog(c.logFile).tail(1000))
      if ((jsonDecode(l) as Map<String, Object?>)['event'] ==
          'fps_launch_option')
        jsonDecode(l) as Map<String, Object?>,
  ];

  FpsSession fpsOf(Config c) =>
      FpsSession(c, FakeSys(now: 1, step: 0).sys, EventLog(c.logFile));

  setUp(() => root = tempDir());

  test('prepareAll writes every installed game, never a tool', () {
    final c = configWith({});
    stage(c);
    final fps = fpsOf(c)..prepareAll();
    final text = localconfig(c).readAsStringSync();
    final mango = 'MANGOHUD=1 MANGOHUD_CONFIGFILE=${fps.confPath} %command%';
    expect(launchOption(text, 10), mango);
    expect(launchOption(text, 30), mango);
    expect(launchOption(text, 20), 'mangohud %command%');
    expect(launchOption(text, 40), isNull);
    final e = events(c).single;
    expect(e['result'], 'all');
    expect(e['games'], {'added': 2, 'user mangohud': 1});
    expect(File(fps.confPath).existsSync(), true);
  });

  test('an uninstalled game with our stale option is repointed', () {
    final c = configWith({});
    stage(c);
    localconfig(c).writeAsStringSync(
      vdf.replaceFirst(
        '"20"',
        '"99"\n\t\t\t\t\t{\n\t\t\t\t\t\t"LaunchOptions"\t\t'
            '"MANGOHUD=1 MANGOHUD_CONFIGFILE=/s/mangohud.conf %command%"\n'
            '\t\t\t\t\t}\n\t\t\t\t\t"20"',
      ),
    );
    final fps = fpsOf(c)..prepareAll();
    expect(
      launchOption(localconfig(c).readAsStringSync(), 99),
      'MANGOHUD=1 MANGOHUD_CONFIGFILE=${fps.confPath} %command%',
    );
    expect(events(c).single['games'], {
      'added': 2,
      'user mangohud': 1,
      'updated': 1,
    });
  });

  test('prepareLaunch covers the other installed games too', () {
    final c = configWith({});
    stage(c);
    fpsOf(c).prepareLaunch(30);
    final text = localconfig(c).readAsStringSync();
    expect(launchOption(text, 10), startsWith('MANGOHUD=1 '));
    final e = events(c).single;
    expect((e['appid'], e['result']), (30, 'added'));
    expect(e['games'], {'added': 2, 'user mangohud': 1});
  });

  test("a scratch data dir never writes kuhy's real Steam config", () {
    final c = configWith({
      'GAME_RESEARCH_STEAM_ROOT': p.join(root.path, '.local', 'share', 'Steam'),
    });
    stage(c);
    fpsOf(c)
      ..prepareAll()
      ..prepareLaunch(10);
    expect(localconfig(c).readAsStringSync(), vdf);
    expect(File(fpsOf(c).confPath).existsSync(), false);
    expect(
      [for (final e in events(c)) e['result']],
      ['skipped scratch data', 'skipped scratch data'],
    );
  });

  test('the default data dir writes the real Steam config', () {
    final c = configWith({
      'GAME_RESEARCH_STEAM_ROOT': p.join(root.path, '.local', 'share', 'Steam'),
      'GAME_RESEARCH_DATA': p.join(root.path, 'data', 'game-research'),
    });
    stage(c);
    fpsOf(c).prepareAll();
    expect(launchOption(localconfig(c).readAsStringSync(), 10), isNotNull);
  });

  test('prepareAll skips while Steam runs', () {
    final c = configWith({});
    stage(c);
    Directory(p.join(c.procRoot, '55')).createSync();
    File(p.join(c.procRoot, '55', 'cmdline')).writeAsStringSync('steam');
    File(c.steamPidFile).writeAsStringSync('55');
    fpsOf(c).prepareAll();
    expect(localconfig(c).readAsStringSync(), vdf);
    expect(events(c).single['result'], 'skipped steam running');
  });

  test('the wrapper writes the options at start', () async {
    final c = configWith({});
    stage(c);
    final server = await serve(c, FakeSys(now: 1, step: 0).sys, port: 0);
    addTearDown(server.close);
    expect(events(c).single['result'], 'all');
    expect(launchOption(localconfig(c).readAsStringSync(), 10), isNotNull);
  });
}
