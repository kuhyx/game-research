import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/steam.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';
import '../support/session_harness.dart';

const game = SteamGame(appid: 1, name: 'Game');

void main() {
  late Harness h;

  setUp(() => h = Harness());

  Future<StartError> failedStart() async {
    try {
      await h.controller.start(game);
    } on StartError catch (e) {
      return e;
    }
    fail('start should have failed');
  }

  bool dataHasFolders() =>
      Directory(h.config.dataDir).existsSync() &&
      Directory(h.config.dataDir).listSync().isNotEmpty;

  test('a missing output fails closed', () async {
    h.fake.onRun = (c) =>
        c.exe == 'xrandr' ? ok('HDMI-0 connected 1x1+0+0') : null;
    final e = await failedStart();
    expect(e.message, 'output DP-2 missing');
    expect(h.controller.lastError, 'output DP-2 missing');
    expect(h.controller.state()['error'], 'output DP-2 missing');
    expect(h.controller.recording, isFalse);
    expect(dataHasFolders(), isFalse);
  });

  test('no working encoder fails closed', () async {
    h.failRuns.add('ffmpeg');
    final e = await failedStart();
    expect(e.message, 'no working video encoder');
    expect(dataHasFolders(), isFalse);
  });

  test('a failing sxhkd start leaves no empty folder', () async {
    h.failRuns.add('systemd-run');
    final e = await failedStart();
    expect(e.message, contains('sxhkd did not start'));
    expect(dataHasFolders(), isFalse);
    expect(h.fake.of('systemctl'), hasLength(2), reason: 'keys released');
    expect(h.fake.calls.where((c) => c.isStart), isEmpty);
  });

  test('an i3 chord collision stops the start', () async {
    final i3 = File(p.join(h.root.path, 'i3'))
      ..writeAsStringSync('bindsym Mod4+F3 exec x\n');
    h = Harness(extra: {'GAME_RESEARCH_I3_CONFIG': i3.path});
    final e = await failedStart();
    expect(e.message, 'i3 already binds super + F3');
    expect(dataHasFolders(), isFalse);
  });

  test('ffmpeg failing to launch cleans up and keeps its own error', () async {
    h.failStarts.add('ffmpeg');
    await expectLater(
      h.controller.start(game),
      throwsA(isA<ProcessException>()),
    );
    expect(dataHasFolders(), isFalse);
    expect(h.fake.of('systemctl'), hasLength(2));
    expect(h.controller.recording, isFalse);
  });

  test('a steam launch failure ends the session and reports it', () async {
    h.failStarts.add('steam');
    final e = await failedStart();
    expect(e.message, contains('steam did not start'));
    expect(h.controller.lastError, e.message);
    expect(h.controller.recording, isFalse);
    expect(h.meta, containsPair('ended_by', 'launch-failed'));
    expect(h.ffmpeg.signals, isNotEmpty);
  });

  test('a good start clears the last error', () async {
    h.fake.onRun = (c) => c.exe == 'xrandr' ? bad() : null;
    await failedStart();
    expect(h.controller.lastError, isNotEmpty);
    h.fake.onRun = (c) => c.exe == 'xrandr' ? ok(kXrandr) : null;
    await h.controller.start(game);
    expect(h.controller.lastError, '');
    await h.controller.stop();
  });
}
