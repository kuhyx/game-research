// Stage 1 runs on the recording's absolute timeline: a frame's pts is its
// wall time - t0, and the first frame's pts is the recorder start-up delay
// (start_time), not 0. ffmpeg's `-ss` is start-relative and its output is
// shifted by -start_time unless told otherwise, so every call says so.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/stage1.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/sampling.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

/// True when `-seek_timestamp 1` comes before `-ss`, and `-ss` before `-i`.
void expectAbsoluteSeek(List<String> args) {
  expect(
    args,
    containsAllInOrder(['-seek_timestamp', '1', '-ss', anything, '-i']),
  );
}

void main() {
  late Fixture fx;
  late FakeSys fake;
  late Stage1 stage;

  setUp(() {
    fx = Fixture();
    fake = FakeSys()
      ..onRun = ffmpegFake
      ..onStart = ffmpegStart;
    stage = Stage1(fx.session.path, fake.sys, stillS: 2);
  });

  group('argv', () {
    test('detect keeps the file timestamps (-copyts)', () async {
      Directory(p.join(fx.session.path, 'analysis')).createSync();
      await stage.detect(40);
      expect(fake.calls.single.args, contains('-copyts'));
    });

    test('extractFrames seeks by absolute timestamp', () async {
      await stage.extractFrames(const [
        SampleFrame(t: 9, kind: FrameKind.scene, file: 'f_0001.png'),
      ], (_, _) {});
      expectAbsoluteSeek(fake.calls.single.args);
      expect(fake.calls.single.args, containsAllInOrder(['-ss', '9.000']));
    });

    test('clips seek by absolute timestamp', () async {
      await stage.clips([
        const Marker(wallUnix: 1, offsetS: 30, tag: MarkerTag.note),
      ]);
      expectAbsoluteSeek(fake.calls.single.args);
      expect(fake.calls.single.args, containsAllInOrder(['-ss', '25.000']));
    });
  });

  group('real ffmpeg, start_time 1.3', () {
    late Stage1 real;

    // 2 s black then 2 s white; the cut sits at 2.0 + 1.3 = 3.3 absolute.
    setUp(() async {
      const graph =
          'color=black:s=64x64:r=10:d=2[a];'
          'color=white:s=64x64:r=10:d=2[b];[a][b]concat=n=2:v=1:a=0';
      final made = await Process.run('ffmpeg', [
        '-v', 'error', '-nostdin', '-f', 'lavfi', '-i', graph, //
        '-output_ts_offset', '1.3', '-c:v', 'libx264', '-g', '10', '-y',
        p.join(fx.session.path, 'recording.mkv'),
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');
      real = Stage1(fx.session.path, const Sys(), stillS: 1);
    });

    Future<int> luma(String png) async {
      final r = await Process.run('ffmpeg', [
        '-v', 'error', '-i', png, '-vf', 'crop=1:1:0:0,format=gray', //
        '-f', 'rawvideo', '-',
      ], stdoutEncoding: null);
      return (r.stdout as List<int>).first;
    }

    test('the scene cut is reported at its absolute time', () async {
      Directory(p.join(fx.session.path, 'analysis')).createSync();
      final (scenes, _) = await real.detect(4);
      expect(scenes.single, closeTo(3.3, 0.15));
    });

    test('a frame at an absolute time shows that moment', () async {
      Directory(p.join(fx.session.path, 'analysis')).createSync();
      await real.extractFrames(const [
        SampleFrame(t: 2.5, kind: FrameKind.scene, file: 'before.png'),
        SampleFrame(t: 3.6, kind: FrameKind.scene, file: 'after.png'),
      ], (_, _) {});
      expect(await luma(fx.out('frames/before.png').path), lessThan(30));
      expect(await luma(fx.out('frames/after.png').path), greaterThan(220));
    });
  });
}
