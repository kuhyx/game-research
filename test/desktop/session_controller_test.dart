import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/steam.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';
import '../support/session_harness.dart';

const game = SteamGame(appid: 730, name: 'Counter: Strike!');

void main() {
  late Harness h;

  setUp(() => h = Harness());

  test('idle state names the target and no session', () {
    expect(h.controller.recording, isFalse);
    expect(h.controller.state(), {
      'recording': false,
      'error': '',
      'target': h.config.defaultTarget,
    });
  });

  test('start brings up keys, recorder, flash and the watcher', () async {
    await h.controller.start(game);
    expect(h.controller.recording, isTrue);
    final exes = h.fake.calls.map((c) => c.exe).toList();
    expect(
      exes,
      containsAllInOrder([
        'xrandr',
        'ffmpeg',
        'systemctl',
        'systemd-run',
        'ffmpeg',
        'python3',
      ]),
    );
    expect(h.fake.of('steam'), isEmpty, reason: 'SessionFlow launches');
    expect(h.events, ['record_start']);
    final dir = h.sessionDir;
    expect(p.basename(dir.path), endsWith('-counter-strike'));
    expect(h.meta, containsPair('state', 'recording'));
    expect(h.meta, containsPair('appid', 730));
    expect(h.meta, containsPair('encoder', 'hevc_nvenc'));
    expect(h.meta, containsPair('output', 'DP-0'));
    expect(h.meta, containsPair('output_why', 'primary'));
    final session = h.controller.state()['session']! as Map<String, Object?>;
    expect(session['appid'], 730);
    expect(session['id'], p.basename(dir.path));
    expect(h.controller.lastError, '');
    await h.controller.stop();
  });

  test('a second start is refused while recording', () async {
    await h.controller.start(game);
    await expectLater(h.controller.start(game), throwsA(isA<StartError>()));
    await h.controller.stop();
  });

  test('markers: plain, held with a note, asked through dmenu', () async {
    await h.controller.start(game);
    expect(await h.controller.marker(MarkerTag.good), isNull);
    final hold = await h.controller.marker(MarkerTag.note, hold: true);
    expect(hold, 1);
    expect(
      h.controller.state()['session'],
      containsPair('markers', {'good': 1, 'bad': 0, 'confusing': 0, 'note': 1}),
    );
    expect(await h.controller.marker(MarkerTag.bad, ask: true), isNull);
    await settle();
    expect(h.controller.note(99, 'x'), isFalse);
    expect(h.controller.note(hold!, '  first line  \nsecond'), isTrue);
    expect(h.controller.note(hold, 'again'), isFalse);
    final lines = h.markerLines;
    expect(lines.map((m) => m['tag']), ['good', 'bad', 'note']);
    expect(lines.map((m) => m['note']), ['', 'asked note', 'first line']);
    expect(h.fake.of('faketick').map((c) => c.args.single), [
      'good',
      'note',
      'bad',
    ]);
    await h.controller.stop();
  });

  test('note and marker without a session', () async {
    expect(h.controller.note(1, 'x'), isFalse);
    expect(
      () => h.controller.marker(MarkerTag.good),
      throwsA(isA<StateError>()),
    );
  });

  test('stop finalises: keys, flash, chapters, meta, analysis job', () async {
    await h.controller.start(game);
    await h.controller.marker(MarkerTag.good);
    await h.controller.stop();
    expect(h.controller.recording, isFalse);
    expect(h.ffmpeg.signals, [ProcessSignal.sigint]);
    expect(h.meta, containsPair('state', 'stopped'));
    expect(h.meta, containsPair('ended_by', 'button'));
    expect(h.meta, containsPair('duration_s', 42.5));
    expect(h.meta.containsKey('error'), isFalse);
    expect(
      File(p.join(h.sessionDir.path, 'recording.mkv')).readAsStringSync(),
      'chaptered',
    );
    final job = h.fake.calls.last;
    expect(job.args, [h.sessionDir.path]);
    expect(job.mode, ProcessStartMode.detached);
    await h.controller.stop();
    expect(h.fake.calls.last, same(job), reason: 'stop is idempotent');
    expect(
      () => h.controller.marker(MarkerTag.good),
      throwsA(isA<StateError>()),
    );
  });

  test('stop closes held notes empty and cancels a dmenu line', () async {
    h.dmenuHangs = true;
    await h.controller.start(game);
    await h.controller.marker(MarkerTag.note, hold: true);
    await h.controller.marker(MarkerTag.confusing, ask: true);
    await settle();
    final both = Future.wait([
      h.controller.stop(endedBy: 'hotkey'),
      h.controller.stop(endedBy: 'ignored'),
    ]);
    expect(() => h.controller.marker(MarkerTag.good), throwsStateError);
    await both;
    expect(h.meta, containsPair('ended_by', 'hotkey'));
    expect(h.markerLines.map((m) => m['tag']).toSet(), {'note', 'confusing'});
    expect(h.markerLines.map((m) => m['note']), everyElement(''));
  });

  test('a chapter failure is reported and no analysis starts', () async {
    await h.controller.start(game);
    h.failRuns.add('ffprobe');
    await h.controller.stop();
    expect(h.meta['error'], contains('ffprobe cannot read'));
    expect(h.controller.lastError, contains('ffprobe cannot read'));
    expect(
      h.fake.calls.where((c) => c.exe.endsWith('game_research_analyze')),
      isEmpty,
    );
  });

  test('ffmpeg dying ends the session as recorder-exit', () async {
    await h.controller.start(game);
    h.ffmpeg.exitWith(1);
    await h.untilStopped();
    expect(h.meta, containsPair('ended_by', 'recorder-exit'));
  });

  test('the game exiting ends the session as game-exit', () async {
    h.gameRuns(730);
    await h.controller.start(game);
    await settle();
    h.gameExits();
    await h.untilStopped();
    expect(h.meta, containsPair('ended_by', 'game-exit'));
  });
}
