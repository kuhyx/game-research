import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/gsr_args.dart';
import 'package:game_research/core/recorder_args.dart';
import 'package:game_research/core/xrandr.dart';

void main() {
  const dp0 = Output(name: 'DP-0', width: 3840, height: 2160);
  RecordSpec spec({Output output = dp0, String audio = 'default'}) =>
      RecordSpec(
        output: output,
        display: ':0',
        fps: 30,
        t0Unix: 1700000000.5,
        out: '/d/recording.mkv',
        audio: audio,
        codec: kGsr,
      );

  test('the probe lists monitors only (never the webcam)', () {
    expect(gsrProbeArgs, [kGsr, '--list-monitors']);
  });

  test('gsrLists finds the output by its RandR name', () {
    const listing = 'HDMI-0|2560x1440\nDP-0|3840x2160\n';
    expect(gsrLists(listing, dp0), isTrue);
    expect(
      gsrLists(listing, const Output(name: 'DP-2', width: 1, height: 1)),
      isFalse,
    );
    expect(gsrLists('', dp0), isFalse);
    // An explicit WxH+X+Y needs any monitor at all (region capture).
    const region = Output(name: 'geometry', width: 10, height: 10);
    expect(gsrLists(listing, region), isTrue);
    expect(gsrLists('', region), isFalse);
  });

  test('30 fps HEVC on the GPU, one keyframe a second, no cursor', () {
    final a = gsrRecordArgs(spec());
    expect(a.first, kGsr);
    expect(a, containsAllInOrder(['-w', 'DP-0']));
    expect(a, containsAllInOrder(['-f', '30']));
    expect(a, containsAllInOrder(['-k', 'hevc']));
    expect(a, containsAllInOrder(['-keyint', '1']));
    // vfr (gsr's default): frames keep their capture times; cfr can stall
    // the encoder at 1-2 fps when the game drops frames (man page).
    expect(a, isNot(contains('-fm')));
    expect(a, containsAllInOrder(['-cursor', 'no']));
    expect(a, containsAllInOrder(['-bm', 'qp', '-q', 'very_high']));
    expect(a, containsAllInOrder(['-c', 'mkv']));
    expect(a, containsAllInOrder(['-encoder', 'gpu']));
    expect(a, containsAllInOrder(['-write-first-frame-ts', 'yes']));
    expect(a.sublist(a.length - 2), ['-o', '/d/recording.mkv']);
  });

  test('game audio from the default sink monitor, Opus, never a mic', () {
    final a = gsrRecordArgs(spec());
    expect(a, containsAllInOrder(['-a', 'default_output', '-ac', 'opus']));
    final mon = gsrRecordArgs(spec(audio: 'alsa_output.x.monitor'));
    expect(mon, containsAllInOrder(['-a', 'alsa_output.x.monitor']));
    for (final args in [a, mon]) {
      expect(args.join(' '), isNot(contains('default_input')));
    }
    expect(
      () => gsrRecordArgs(spec(audio: 'alsa_input.mic')),
      throwsArgumentError,
    );
    // lavfi (tests): no audio input at all.
    expect(gsrRecordArgs(spec(audio: 'lavfi')), isNot(contains('-a')));
  });

  test('an explicit geometry is a region capture', () {
    const g = Output(name: 'geometry', width: 100, height: 50, x: 3, y: 4);
    final a = gsrRecordArgs(spec(output: g));
    expect(a, containsAllInOrder(['-w', 'region', '-region', '100x50+3+4']));
  });

  test('gsr stamps its first frame 0.12 s after capture', () {
    // Measured 2026-11-11 on kuhy's RTX 3090, 4K30, tool/marker_lag.py:
    // 0.112 and 0.134 s between a flash's draw time and its frame.
    expect(kGsrStampLagS, 0.12);
  });

  test('the first-frame file sits beside the video', () {
    expect(gsrTsPath('/d/recording.mkv'), '/d/recording.mkv.ts');
  });

  test('parseFirstFrameTs reads the realtime column in seconds', () {
    const text =
        'monotonic_microsec\trealtime_microsec\n'
        '123456789\t1700000000750000\n';
    expect(parseFirstFrameTs(text), closeTo(1700000000.75, 1e-6));
    expect(parseFirstFrameTs('123 1700000001000000'), 1700000001.0);
    expect(parseFirstFrameTs(''), isNull);
    expect(
      parseFirstFrameTs('monotonic_microsec\trealtime_microsec\n'),
      isNull,
    );
    expect(parseFirstFrameTs('1 x\n'), isNull);
  });

  test('embedChaptersArgs shifts the input by the first-frame delay', () {
    final a = embedChaptersArgs(
      '/d/r.mkv',
      '/d/r.ffmeta',
      '/d/t.mkv',
      shiftS: 0.25,
    );
    expect(a, containsAllInOrder(['-itsoffset', '0.250000', '-i', '/d/r.mkv']));
    expect(
      embedChaptersArgs('/d/r.mkv', '/d/r.ffmeta', '/d/t.mkv'),
      isNot(contains('-itsoffset')),
    );
  });
}
