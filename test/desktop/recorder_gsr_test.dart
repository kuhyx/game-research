import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/gsr_args.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/recorder_args.dart';
import 'package:game_research/core/xrandr.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/recording_flag.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const _dp0 = Output(name: 'DP-0', width: 3840, height: 2160);
const _listing = 'HDMI-0|2560x1440\nDP-0|3840x2160\n';

void main() {
  late Directory root;
  late FakeSys fake;
  late String out;

  Recorder recorder([Map<String, String> extra = const {}]) => Recorder(
    testConfig(root, extra: extra),
    fake.sys,
    firstFrameTimeout: const Duration(milliseconds: 200),
    poll: const Duration(milliseconds: 5),
  );

  RecordSpec spec(String codec) => RecordSpec(
    output: _dp0,
    display: ':99',
    fps: 30,
    t0Unix: 1700000000.5,
    out: out,
    audio: 'lavfi',
    codec: codec,
  );

  setUp(() {
    root = tempDir();
    fake = FakeSys();
    Directory(p.join(root.path, 'data')).createSync(recursive: true);
    out = p.join(root.path, 'data', 'recording.mkv');
  });

  group('probeCapture', () {
    test('gpu-screen-recorder when it lists the output', () async {
      fake.onRun = (c) => c.exe == kGsr ? ok(_listing) : ok();
      expect(await recorder().probeCapture(_dp0), kGsr);
      expect(fake.calls.single.args, ['--list-monitors']);
      expect(fake.calls.single.env, {'DISPLAY': ':99'});
    });

    test('x11grab encoders when gsr fails (Xvfb has no GPU GL)', () async {
      fake.onRun = (c) =>
          c.exe == kGsr ? bad('failed to load opengl', 22) : ok();
      expect(await recorder().probeCapture(_dp0), kNvencHevc);
      fake.calls.clear();
      fake.onRun = (c) => c.exe == kGsr ? ok('HDMI-0|1x1\n') : ok();
      expect(await recorder().probeCapture(_dp0), kNvencHevc);
    });

    test(
      'CAPTURE=x11grab never asks gsr; CAPTURE=gsr never falls back',
      () async {
        fake.onRun = (c) => c.exe == kGsr ? ok(_listing) : ok();
        final x = recorder({'GAME_RESEARCH_CAPTURE': 'x11grab'});
        expect(await x.probeCapture(_dp0), kNvencHevc);
        expect(fake.of(kGsr), isEmpty);
        fake.onRun = (c) => c.exe == kGsr ? bad() : ok();
        final g = recorder({'GAME_RESEARCH_CAPTURE': 'gsr'});
        expect(await g.probeCapture(_dp0), isNull);
      },
    );
  });

  group('start with gsr', () {
    test('waits for the first frame, raises the recording flag', () async {
      fake.onStart = (c) {
        File(gsrTsPath(out)).writeAsStringSync('1 1700000000750000\n');
        return FakeProcess();
      };
      final rec = await recorder().start(spec(kGsr));
      expect(fake.calls.single.exe, kGsr);
      expect(rec.codec, kGsr);
      final flag = RecordingFlag(p.join(root.path, 'data'));
      expect(flag.live, isTrue);
      await rec.stop();
      expect(flag.live, isFalse);
    });

    test('gsr dying before a frame falls back to x11grab', () async {
      fake.onStart = (c) =>
          c.exe == kGsr ? FakeProcess(exit: 1) : FakeProcess();
      final rec = await recorder().start(spec(kGsr));
      expect(fake.started, hasLength(2));
      expect(fake.calls.last.exe, 'ffmpeg');
      expect(rec.codec, kNvencHevc);
      await rec.stop();
    });

    test('alive past the timeout without the time file: gsr is kept', () async {
      // The first-frame file may only appear at exit; finish() needs it.
      fake.onStart = (c) => FakeProcess();
      final rec = await recorder().start(spec(kGsr));
      expect(fake.started, hasLength(1));
      expect(fake.started.single.signals, isEmpty);
      expect(rec.codec, kGsr);
      await rec.stop();
    });

    test('gsr dead and no ffmpeg encoder: StartError, flag down', () async {
      fake
        ..onStart = ((c) => FakeProcess(exit: 1))
        ..onRun = ((_) => bad());
      await expectLater(
        recorder().start(spec(kGsr)),
        throwsA(isA<StartError>()),
      );
      expect(RecordingFlag(p.join(root.path, 'data')).live, isFalse);
    });
  });

  group('finish', () {
    test(
      'gsr: the remux shifts by first frame - t0, even with no markers',
      () async {
        File(out).writeAsStringSync('video');
        File(gsrTsPath(out)).writeAsStringSync('1 1700000000750000\n');
        fake.onRun = (c) {
          if (c.exe == 'ffprobe') return ok('{"format":{"duration":"9.5"}}');
          File(c.args.last).writeAsStringSync('shifted');
          return ok();
        };
        final rec = Recording(FakeProcess(exit: 0), codec: kGsr, out: out);
        expect(
          await recorder().finish(rec, const <Marker>[], 1700000000.5),
          9.75,
        );
        final remux = fake.of('ffmpeg').single.args;
        expect(
          remux,
          containsAllInOrder(['-itsoffset', '0.250000', '-i', out]),
        );
        expect(File(out).readAsStringSync(), 'shifted');
      },
    );

    test('gsr without its first-frame file fails closed', () async {
      File(out).writeAsStringSync('video');
      fake.onRun = (_) => ok('{"format":{"duration":"9.5"}}');
      final rec = Recording(FakeProcess(exit: 0), codec: kGsr, out: out);
      await expectLater(
        recorder().finish(rec, const <Marker>[], 1700000000.5),
        throwsStateError,
      );
    });

    test('x11grab: no shift, no remux without markers', () async {
      fake.onRun = (_) => ok('{"format":{"duration":"9.5"}}');
      final rec = Recording(FakeProcess(exit: 0), out: out);
      expect(await recorder().finish(rec, const <Marker>[], 1), 9.5);
      expect(fake.of('ffmpeg'), isEmpty);
    });
  });
}
