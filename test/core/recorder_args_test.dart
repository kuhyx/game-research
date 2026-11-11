import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/recorder_args.dart';
import 'package:game_research/core/xrandr.dart';

void main() {
  const out = Output(name: 'DP-2', width: 3840, height: 2160);
  RecordSpec spec({String audio = 'default', String codec = kNvencHevc}) =>
      RecordSpec(
        output: out,
        display: ':0',
        fps: 60,
        t0Unix: 1700000000.5,
        out: '/d/recording.mkv',
        audio: audio,
        codec: codec,
      );

  test('x11grab of the output region, wall-clock stamped from t0', () {
    final a = ffmpegRecordArgs(spec());
    expect(a.first, 'ffmpeg');
    expect(
      a,
      containsAllInOrder(['-f', 'x11grab', '-video_size', '3840x2160']),
    );
    expect(a, containsAllInOrder(['-framerate', '60', '-i', ':0+0,0']));
    expect(a, containsAllInOrder(['-use_wallclock_as_timestamps', '1']));
    expect(a, containsAllInOrder(['-output_ts_offset', '-1700000000.500000']));
    expect(a, contains('-copyts'));
    expect(a, containsAllInOrder(['-draw_mouse', '0']));
  });

  test('NVENC near-lossless HEVC, FLAC audio, Matroska', () {
    final a = ffmpegRecordArgs(spec());
    expect(a, containsAllInOrder(['-c:v', 'hevc_nvenc', '-preset', 'p5']));
    expect(a, containsAllInOrder(['-rc', 'vbr', '-cq', '14', '-b:v', '0']));
    expect(a, containsAllInOrder(['-c:a', 'flac']));
    expect(a, containsAllInOrder(['-f', 'matroska', '/d/recording.mkv']));
    expect(a.join(' '), isNot(contains('libopus')));
    expect(a.join(' '), isNot(contains('mp3')));
  });

  test('game audio comes from the default sink monitor, never a mic', () {
    final a = ffmpegRecordArgs(spec());
    expect(a, containsAllInOrder(['-f', 'pulse', '-i', '@DEFAULT_MONITOR@']));
  });

  test('a named monitor source must be a .monitor (no microphone)', () {
    final a = ffmpegRecordArgs(spec(audio: 'alsa_output.x.monitor'));
    expect(a, contains('alsa_output.x.monitor'));
    expect(
      () => ffmpegRecordArgs(spec(audio: 'alsa_input.mic')),
      throwsArgumentError,
    );
  });

  test('test audio is wall-clock stamped silence', () {
    final a = ffmpegRecordArgs(spec(audio: 'lavfi'));
    expect(
      a,
      containsAllInOrder(['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo']),
    );
    expect(a.join(' '), contains('RTCTIME'));
  });

  test('libx264 fallback stays high quality', () {
    final a = ffmpegRecordArgs(spec(codec: kX264));
    expect(a, containsAllInOrder(['-c:v', 'libx264', '-crf', '12']));
  });

  test('pickEncoder prefers NVENC HEVC, then H.264 NVENC, then x264', () {
    expect(pickEncoder({kX264, kNvencHevc}), kNvencHevc);
    expect(pickEncoder({kX264, kNvencH264}), kNvencH264);
    expect(pickEncoder({kX264}), kX264);
    expect(pickEncoder({}), isNull);
    final h264 = ffmpegRecordArgs(spec(codec: kNvencH264));
    expect(h264, containsAllInOrder(['-c:v', 'h264_nvenc']));
  });

  test('probe argv encodes one frame to null', () {
    final a = encoderProbeArgs(kNvencHevc);
    expect(a, containsAllInOrder(['-c:v', 'hevc_nvenc', '-f', 'null', '-']));
  });

  test('embedChaptersArgs remuxes without re-encoding', () {
    final a = embedChaptersArgs('/d/r.mkv', '/d/r.ffmeta', '/d/r.tmp.mkv');
    expect(a, containsAllInOrder(['-map_chapters', '1', '-c', 'copy']));
    expect(a.last, '/d/r.tmp.mkv');
  });
}
