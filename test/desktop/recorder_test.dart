import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/recorder_args.dart';
import 'package:game_research/core/xrandr.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

// kuhy's real layout (2026-11-11): DP-0 primary, HDMI-0 right of it.
const _monitors = '''
Monitors: 2
 0: +*DP-0 3840/620x2160/340+0+0  DP-0
 1: +HDMI-0 2560/698x1440/393+3840+0  HDMI-0
''';

String probeJson(num seconds) => jsonEncode({
  'format': {'duration': '$seconds'},
});

void main() {
  late Directory root;
  late FakeSys fake;

  Recorder recorder([Map<String, String> extra = const {}]) =>
      Recorder(testConfig(root, extra: extra), fake.sys);

  setUp(() {
    root = tempDir();
    fake = FakeSys();
  });

  test('StartError prints its message', () {
    expect(const StartError('x').toString(), 'StartError: x');
  });

  group('resolveOutput', () {
    test('an explicit geometry needs no xrandr', () async {
      final o = await recorder({'GAME_RESEARCH_OUTPUT': '100x50+3+4'})
          .resolveOutput();
      expect(o?.output.geometry, '100x50+3+4');
      expect(o?.why, 'geometry');
      expect(fake.calls, isEmpty);
    });

    test('the monitor under the game window, no output name', () async {
      // 2026-11-11 live bug: the default DP-2 does not exist on :0.
      fake.onRun = (_) => ok(_monitors);
      const rect = (x: 3840, y: 0, width: 2560, height: 1440);
      final o = await recorder().resolveOutput(window: rect);
      expect(o?.output.name, 'HDMI-0');
      expect(o?.why, 'window');
      expect(fake.calls.single.args, ['--listmonitors']);
      expect(fake.calls.single.env, {'DISPLAY': ':99'});
      expect((await recorder().resolveOutput())?.output.name, 'DP-0');
    });

    test('a failing xrandr or no monitor gives null', () async {
      fake.onRun = (_) => ok('Monitors: 0\n');
      expect(await recorder().resolveOutput(), isNull);
      fake.onRun = (_) => bad('no display');
      expect(await recorder().resolveOutput(), isNull);
    });
  });

  group('probeEncoder', () {
    test('the first working codec in preference order wins', () async {
      expect(await recorder().probeEncoder(), kNvencHevc);
      expect(fake.calls, hasLength(1));
    });

    test('falls back down the list', () async {
      fake.onRun = (c) => c.args.contains(kX264) ? ok() : bad();
      expect(await recorder().probeEncoder(), kX264);
      expect(fake.calls, hasLength(3));
    });

    test('none working gives null', () async {
      fake.onRun = (_) => bad();
      expect(await recorder().probeEncoder(), isNull);
    });
  });

  group('start and Recording', () {
    test(
      'ffmpeg starts on the display and logs stderr beside the video',
      () async {
        fake.onStart = (_) => FakeProcess(stderrText: 'warn line\n');
        final out = p.join(root.path, 'recording.mkv');
        final rec = await recorder().start(
          RecordSpec(
            output: const Output(name: 'DP-2', width: 10, height: 10),
            display: ':99',
            fps: 30,
            t0Unix: 5,
            out: out,
            audio: 'lavfi',
          ),
        );
        final call = fake.calls.single;
        expect(call.exe, 'ffmpeg');
        expect(call.args.last, out);
        expect(call.env, {'DISPLAY': ':99'});
        expect(rec.stopTimeout, const Duration(seconds: 20));
        fake.started.single.exitWith(0);
        expect(await rec.exited, 0);
        await settle();
        expect(
          File(p.join(root.path, 'ffmpeg.log')).readAsStringSync(),
          'warn line\n',
        );
      },
    );

    test('stop sends SIGINT and waits for ffmpeg', () async {
      final process = FakeProcess();
      final rec = Recording(process);
      expect(await rec.stop(), -ProcessSignal.sigint.signalNumber);
      expect(process.signals, [ProcessSignal.sigint]);
    });

    test('a stuck ffmpeg gets SIGKILL after the timeout', () async {
      final process = FakeProcess(exitOn: {ProcessSignal.sigkill});
      final rec = Recording(
        process,
        stopTimeout: const Duration(milliseconds: 10),
      );
      expect(await rec.stop(), -ProcessSignal.sigkill.signalNumber);
      expect(process.signals, [ProcessSignal.sigint, ProcessSignal.sigkill]);
    });
  });

  group('duration', () {
    test('ffprobe json gives seconds', () async {
      fake.onRun = (_) => ok(probeJson(12.5));
      expect(await recorder().duration('v.mkv'), 12.5);
      expect(fake.calls.single.exe, 'ffprobe');
    });

    test('a failing or garbled ffprobe gives null', () async {
      fake.onRun = (_) => bad();
      expect(await recorder().duration('v.mkv'), isNull);
      fake.onRun = (_) => ok('{}');
      expect(await recorder().duration('v.mkv'), isNull);
    });
  });

  group('embedChapters', () {
    late String video;
    final markers = [
      const Marker(wallUnix: 1, offsetS: 2, tag: MarkerTag.good, note: 'n'),
    ];

    setUp(() {
      video = p.join(root.path, 'recording.mkv');
      File(video).writeAsStringSync('original');
    });

    test('an unreadable video throws', () async {
      fake.onRun = (_) => bad();
      await expectLater(
        recorder().embedChapters(video, markers),
        throwsA(isA<StateError>()),
      );
    });

    test('no markers: the length only, the file untouched', () async {
      fake.onRun = (_) => ok(probeJson(9));
      expect(await recorder().embedChapters(video, const []), 9);
      expect(fake.calls, hasLength(1));
      expect(File(video).readAsStringSync(), 'original');
    });

    test('markers are remuxed in as chapters and replace the video', () async {
      fake.onRun = (c) {
        if (c.exe == 'ffprobe') return ok(probeJson(30));
        expect(
          File(c.args[c.args.indexOf('ffmetadata') + 2]).readAsStringSync(),
          contains('[CHAPTER]'),
        );
        File(c.args.last).writeAsStringSync('chaptered');
        return ok();
      };
      expect(await recorder().embedChapters(video, markers), 30);
      expect(File(video).readAsStringSync(), 'chaptered');
      expect(File(p.setExtension(video, '.ffmeta')).existsSync(), isFalse);
    });

    test('a failing remux throws and keeps the original', () async {
      fake.onRun = (c) => c.exe == 'ffprobe' ? ok(probeJson(30)) : bad('boom');
      await expectLater(
        recorder().embedChapters(video, markers),
        throwsA(
          isA<StateError>().having((e) => '$e', 'text', contains('boom')),
        ),
      );
      expect(File(video).readAsStringSync(), 'original');
      expect(File(p.setExtension(video, '.ffmeta')).existsSync(), isFalse);
    });
  });
}
