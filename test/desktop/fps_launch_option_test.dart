import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/steam_vdf.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/fps_session.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const appid = 4197610;

/// The fake clock; the fixture log spans [t - 1.0, t + 0.05].
const t = 1000000.0;
const vdfBefore = '''
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
\t\t\t\t\t"4197610"
\t\t\t\t\t{
\t\t\t\t\t\t"LaunchOptions"\t\t"-novid"
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}
\t\t}
\t}
}
''';

void main() {
  late Directory root;
  late Config config;
  late FpsSession fps;
  late FakeSys fake;

  File localconfig([String user = '111']) => File(
    p.join(config.steamRoot, 'userdata', user, 'config', 'localconfig.vdf'),
  );

  List<Map<String, Object?>> events(String name) => [
    for (final l in EventLog(config.logFile).tail(1000))
      if ((jsonDecode(l) as Map<String, Object?>)['event'] == name)
        jsonDecode(l) as Map<String, Object?>,
  ];

  setUp(() {
    root = tempDir();
    fake = FakeSys(now: t, step: 0);
    config = testConfig(
      root,
      extra: {
        'GAME_RESEARCH_REPO': Directory.current.path,
        'GAME_RESEARCH_PROC': p.join(root.path, 'proc'),
        'GAME_RESEARCH_STEAM_PID': p.join(root.path, 'steam.pid'),
      },
    );
    Directory(config.procRoot).createSync();
    fps = FpsSession(config, fake.sys, EventLog(config.logFile));
  });

  void steamRuns() {
    Directory(p.join(config.procRoot, '55')).createSync();
    File(p.join(config.procRoot, '55', 'cmdline')).writeAsStringSync('steam');
    File(config.steamPidFile).writeAsStringSync('55');
  }

  group('prepareLaunch', () {
    test('writes the launch option and the app-owned MangoHud config', () {
      localconfig()
        ..createSync(recursive: true)
        ..writeAsStringSync(vdfBefore);
      fps.prepareLaunch(appid);
      expect(
        launchOption(localconfig().readAsStringSync(), appid),
        'MANGOHUD=1 MANGOHUD_CONFIGFILE=${fps.confPath} %command% -novid',
      );
      expect(
        File('${localconfig().path}.game-research.bak').readAsStringSync(),
        vdfBefore,
      );
      final conf = File(fps.confPath).readAsStringSync();
      expect(conf, contains('output_folder=${fps.spoolDir}\n'));
      expect(conf, contains('\nno_display\n'));
      expect(conf, contains('\nautostart_log='));
      expect(Directory(fps.spoolDir).existsSync(), true);
      expect(events('fps_launch_option').single['result'], 'added');
    });

    test('is idempotent: the second call changes nothing', () {
      localconfig()
        ..createSync(recursive: true)
        ..writeAsStringSync(vdfBefore);
      fps.prepareLaunch(appid);
      final once = localconfig().readAsStringSync();
      File('${localconfig().path}.game-research.bak').deleteSync();
      fps.prepareLaunch(appid);
      expect(localconfig().readAsStringSync(), once);
      expect(
        File('${localconfig().path}.game-research.bak').existsSync(),
        false,
      );
      expect(events('fps_launch_option').last['result'], 'present');
    });

    test('skips while Steam runs and says so', () {
      localconfig()
        ..createSync(recursive: true)
        ..writeAsStringSync(vdfBefore);
      steamRuns();
      fps.prepareLaunch(appid);
      expect(localconfig().readAsStringSync(), vdfBefore);
      expect(File(fps.confPath).existsSync(), false);
      expect(
        events('fps_launch_option').single['result'],
        'skipped steam running',
      );
    });

    test('a stale steam.pid is not a running Steam', () {
      File(config.steamPidFile).writeAsStringSync('999');
      localconfig()
        ..createSync(recursive: true)
        ..writeAsStringSync(vdfBefore);
      fps.prepareLaunch(appid);
      expect(events('fps_launch_option').single['result'], 'added');
    });

    test('edits every account, reports one with no apps block', () {
      localconfig()
        ..createSync(recursive: true)
        ..writeAsStringSync(vdfBefore);
      localconfig('222')
        ..createSync(recursive: true)
        ..writeAsStringSync('"UserLocalConfigStore"\n{\n}\n');
      fps.prepareLaunch(appid);
      expect(localconfig().readAsStringSync(), contains('MANGOHUD=1'));
      expect(
        localconfig('222').readAsStringSync(),
        '"UserLocalConfigStore"\n{\n}\n',
      );
      final results = [
        for (final e in events('fps_launch_option')) e['result'],
      ];
      expect(results, ['added', 'error']);
      expect(events('fps_launch_option').last['message'], isNotEmpty);
    });

    test('no account on disk: logged, nothing created', () {
      fps.prepareLaunch(appid);
      expect(
        events('fps_launch_option').single['result'],
        'skipped no localconfig',
      );
      expect(File(fps.confPath).existsSync(), false);
    });

    test("kuhy's own mangohud option is left alone", () {
      localconfig()
        ..createSync(recursive: true)
        ..writeAsStringSync(
          vdfBefore.replaceFirst('-novid', 'mangohud %command%'),
        );
      fps.prepareLaunch(appid);
      expect(
        localconfig().readAsStringSync(),
        contains('"mangohud %command%"'),
      );
      expect(events('fps_launch_option').single['result'], 'user mangohud');
    });

    test('a config template that is missing is an error, not a crash', () {
      final bare = testConfig(
        root,
        extra: {
          'GAME_RESEARCH_REPO': p.join(root.path, 'nowhere'),
          'GAME_RESEARCH_PROC': config.procRoot,
          'GAME_RESEARCH_STEAM_PID': config.steamPidFile,
        },
      );
      localconfig()
        ..createSync(recursive: true)
        ..writeAsStringSync(vdfBefore);
      FpsSession(bare, fake.sys, EventLog(bare.logFile)).prepareLaunch(appid);
      expect(localconfig().readAsStringSync(), vdfBefore);
      expect(events('fps_launch_option').single['result'], 'error');
    });
    test('an unwritable account folder is an error, not a crash', () {
      localconfig()
        ..createSync(recursive: true)
        ..writeAsStringSync(vdfBefore);
      final dir = localconfig().parent;
      Process.runSync('chmod', ['a-w', dir.path]);
      addTearDown(() => Process.runSync('chmod', ['u+w', dir.path]));
      fps.prepareLaunch(appid);
      expect(localconfig().readAsStringSync(), vdfBefore);
      expect(events('fps_launch_option').single['result'], 'error');
    });
  });
}
