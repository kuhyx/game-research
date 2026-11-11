import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/session_flow.dart';
import 'package:game_research/desktop/steam_library.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';
import '../support/session_harness.dart';

const librarian = 4197610;

/// 2026-11-11 live run: the first window found was not one PlayStudy could
/// record and the session stayed dead at 00:00. A failed start now waits for
/// the next window and tries once more.
void main() {
  late Harness h;
  late SessionFlow flow;

  Harness build([Map<String, String> extra = const {}]) {
    final harness = Harness(extra: extra);
    final apps = Directory(p.join(harness.config.steamRoot, 'steamapps'))
      ..createSync(recursive: true);
    File('test/fixtures/appmanifest_$librarian.acf')
        .copySync(p.join(apps.path, 'appmanifest_$librarian.acf'));
    flow = SessionFlow(
      harness.controller,
      SteamLibrary(harness.config.steamRoot),
      every: const Duration(milliseconds: 10),
    );
    return harness;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await settle();
    }
  }

  List<Map<String, Object?>> events(String name) => [
    for (final l in h.log.tail(1000))
      if (jsonDecode(l) case final Map<String, Object?> e
          when e['event'] == name)
        e,
  ];

  Future<void> failFirstWindow() async {
    h.failRuns.add('xrandr');
    await flow.start(librarian);
    h.gameRuns(librarian);
    await until(() => flow.error.isNotEmpty);
  }

  setUp(() => h = build());
  tearDown(() => flow.cancel('test'));

  test('the game window picks the monitor that is recorded', () async {
    await flow.start(librarian);
    h.gameRuns(librarian);
    await until(() => h.controller.recording);
    final start = events('record_start').single;
    expect(start['output'], 'HDMI-0');
    expect(start['output_why'], 'window');
    expect(start['geometry'], '2560x1440+3840+0');
  });

  test(
    'a failed start keeps the error and waits for the next window',
    () async {
      await failFirstWindow();
      expect(flow.error, 'no monitor found');
      expect(flow.phase, Phase.waiting);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(events('window'), hasLength(1), reason: 'same window skipped');
      expect(events('error'), hasLength(1));
      h.failRuns.remove('xrandr');
      h.windowId = '81788930';
      await until(() => h.controller.recording);
      expect(flow.error, '');
      expect(events('window').last['window'], '81788930');
    },
  );

  test('a second failure gives up, error and log line kept', () async {
    await failFirstWindow();
    h.windowId = '81788930';
    await until(() => flow.phase == Phase.idle);
    expect(flow.state()['error'], 'no monitor found');
    expect(events('error'), hasLength(2));
    expect(h.controller.recording, isFalse);
  });

  test('the game quitting after a failed start ends the wait', () async {
    h = build({'GAME_RESEARCH_RELAUNCH_S': '0'});
    final dir = Directory(p.join(h.proc.path, '500'))..createSync();
    File(p.join(dir.path, 'cmdline')).writeAsStringSync('steam');
    File(h.config.steamPidFile).writeAsStringSync('500');
    await failFirstWindow();
    final relaunches = events('relaunch').length;
    h.gameExits();
    await until(() => flow.phase == Phase.idle);
    expect(flow.phase, Phase.idle);
    expect(flow.error, 'no monitor found');
    expect(
      events('relaunch'),
      hasLength(relaunches),
      reason: 'never restart a game kuhy quit',
    );
  });
}
