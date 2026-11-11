import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/session_flow.dart';
import 'package:game_research/desktop/steam_library.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';
import '../support/session_harness.dart';

const librarian = 4197610;

void main() {
  late Harness h;
  late SessionFlow flow;

  Harness build([Map<String, String> extra = const {}]) {
    final harness = Harness(
      extra: {'GAME_RESEARCH_AUTOSTART_S': '0.05', ...extra},
    );
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

  Map<String, Object?> lastEvent(String name) => h.log
      .tail(1000)
      .map((l) => jsonDecode(l) as Map<String, Object?>)
      .lastWhere((e) => e['event'] == name);

  setUp(() => h = build());
  tearDown(() => flow.cancel('test'));

  test('start launches Steam in its own unit when no client runs', () async {
    await flow.start(librarian);
    final run = h.fake.of('systemd-run').single;
    expect(run.args, [
      '--user',
      '--collect',
      '--quiet',
      '--unit',
      'playstudy-steam-18999',
      '--setenv=DISPLAY=:99',
      'steam',
      'steam://rungameid/$librarian',
    ]);
    expect(flow.phase, Phase.waiting);
    expect(lastEvent('steam_client')['pid'], isNull);
    expect(lastEvent('launch')['exit_code'], 0);
    final pending = flow.state()['pending']! as Map<String, Object?>;
    expect(pending, {'appid': librarian});
    expect(flow.lastAppid(), librarian);
  });

  test('a game already running is not launched again', () async {
    // Handing the URI to Steam while the game runs makes Steam show an
    // "error while launching" toast.
    h.gameRuns(librarian);
    await flow.start(librarian);
    expect(h.fake.of('systemd-run'), isEmpty);
    expect(h.fake.of('steam'), isEmpty);
    expect(h.events, contains('already_running'));
    await until(() => h.controller.recording);
  });

  test('a running client gets the URI handed over', () async {
    final dir = Directory(p.join(h.proc.path, '500'))..createSync();
    File(p.join(dir.path, 'cmdline')).writeAsStringSync('/x/ubuntu12_32/steam');
    File(h.config.steamPidFile).writeAsStringSync('500\n');
    await flow.start(librarian);
    expect(h.fake.of('systemd-run'), isEmpty);
    expect(h.fake.of('steam').single.args, ['steam://rungameid/$librarian']);
    expect(lastEvent('steam_client')['pid'], 500);
  });

  test('recording starts once the game window appears', () async {
    await flow.start(librarian);
    await settle();
    expect(h.controller.recording, isFalse);
    h.gameRuns(librarian);
    await until(() => h.controller.recording);
    expect(flow.phase, Phase.recording);
    expect(lastEvent('window'), containsPair('window', h.windowId));
    expect(h.events, containsAllInOrder(['launch', 'window', 'record_start']));
    await settle(); // the exit watch must see the game once
    h.gameExits();
    await h.untilStopped();
    expect(flow.phase, Phase.idle);
    expect(lastEvent('record_stop')['ended_by'], 'game-exit');
  });

  test('Steam that updated without launching gets the URI again', () async {
    // 2026-11-11 real run: Steam finished Librarian's download after the
    // startup URI and never launched it; a second handoff did.
    h = build({'GAME_RESEARCH_RELAUNCH_S': '2'});
    await flow.start(librarian);
    final dir = Directory(p.join(h.proc.path, '500'))..createSync();
    File(p.join(dir.path, 'cmdline')).writeAsStringSync('steam');
    File(h.config.steamPidFile).writeAsStringSync('500');
    await until(() => h.fake.of('steam').isNotEmpty);
    expect(h.fake.of('steam').first.args, ['steam://rungameid/$librarian']);
    expect(h.events, contains('relaunch'));
    h.gameRuns(librarian);
    await until(() => h.controller.recording);
    final hands = h.fake.of('steam').length;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(h.fake.of('steam'), hasLength(hands), reason: 'game up: no more');
  });

  test('a failing handoff is logged and the wait goes on', () async {
    h = build({'GAME_RESEARCH_RELAUNCH_S': '1'});
    await flow.start(librarian);
    final dir = Directory(p.join(h.proc.path, '500'))..createSync();
    File(p.join(dir.path, 'cmdline')).writeAsStringSync('steam');
    File(h.config.steamPidFile).writeAsStringSync('500');
    h.failRuns.add('steam');
    await until(() => h.fake.of('steam').length > 1);
    expect(flow.phase, Phase.waiting);
    expect(lastEvent('launch')['exit_code'], 1);
  });

  test('no relaunch while the client is down or the game runs', () async {
    h = build({'GAME_RESEARCH_RELAUNCH_S': '1'});
    await flow.start(librarian);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(h.fake.of('steam'), isEmpty);
    expect(h.fake.of('systemd-run'), hasLength(1));
  });

  test('a recorder failure after the window shows as the error', () async {
    h.failRuns.add('xrandr');
    await flow.start(librarian);
    h.gameRuns(librarian);
    await until(() => flow.state()['error'] != '');
    expect(flow.state()['error'], contains('output'));
    expect(flow.phase, Phase.idle);
  });

  test('autostart arms, drains and launches the last game', () async {
    expect(flow.arm(), isTrue);
    expect(flow.phase, Phase.armed);
    final pending = flow.state()['pending']! as Map<String, Object?>;
    expect(pending['appid'], librarian);
    expect(pending['total_s'], 0.05);
    expect(pending['deadline_unix'], isA<double>());
    expect(flow.arm(), isFalse, reason: 'already armed');
    await until(() => flow.phase == Phase.waiting);
    expect(h.fake.of('systemd-run'), hasLength(1));
    expect(h.events, containsAllInOrder(['autostart_arm', 'autostart_fire']));
  });

  test('cancel while armed: nothing launches', () async {
    expect(flow.cancel('esc'), isFalse, reason: 'nothing pending');
    flow.arm();
    expect(flow.cancel('esc'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(h.fake.of('systemd-run'), isEmpty);
    expect(lastEvent('cancel'), containsPair('by', 'esc'));
    expect(flow.phase, Phase.idle);
  });

  test('a game missing from the library fails visibly', () async {
    flow.arm(appid: 1);
    await until(() => flow.error.isNotEmpty);
    expect(flow.state()['error'], contains('not in the Steam library'));
    expect(lastEvent('error')['step'], 'pick');
    expect(flow.phase, Phase.idle);
  });

  test('a failing Steam command fails visibly', () async {
    h.failRuns.add('systemd-run');
    await expectLater(flow.start(librarian), throwsA(isA<StartError>()));
    expect(flow.state()['error'], contains('steam launch exited 1'));
    expect(lastEvent('error')['step'], 'launch');
  });

  test('a missing steam binary is a launch error', () async {
    File(h.config.steamPidFile).writeAsStringSync('nonsense');
    final old = h.fake.onRun;
    h.fake.onRun = (c) => c.exe == 'systemd-run'
        ? throw const ProcessException('systemd-run', [], 'gone')
        : old!(c);
    await expectLater(flow.start(librarian), throwsA(isA<StartError>()));
    expect(flow.error, contains('steam did not start'));
  });

  test('a busy flow refuses a second start', () async {
    await flow.start(librarian);
    await expectLater(flow.start(librarian), throwsA(isA<StartError>()));
  });

  test('stop while waiting cancels; a late window records nothing', () async {
    await flow.start(librarian);
    expect(flow.cancel('button'), isTrue);
    h.gameRuns(librarian);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(h.controller.recording, isFalse);
  });

  test('cancel during the Steam command skips the wait', () async {
    final launching = flow.start(librarian);
    expect(flow.phase, Phase.launching);
    expect(flow.cancel('button'), isTrue);
    await launching;
    expect(flow.phase, Phase.idle);
    expect(h.events, isNot(contains('waiting')));
  });

  test('a window that never appears times out with an error', () async {
    h = build({'GAME_RESEARCH_WINDOW_TIMEOUT_S': '3'});
    await flow.start(librarian);
    await until(() => flow.error.isNotEmpty);
    expect(flow.error, 'the game window never appeared');
    expect(lastEvent('error')['step'], 'window');
  });

  test('without a saved game the default (Librarian) is used', () {
    h.parts.targets.settings.merge({'last_appid': 'junk'});
    expect(flow.lastAppid(), librarian);
    h.parts.targets.settings.merge({'last_appid': 7});
    expect(flow.lastAppid(), 7);
  });
}
