import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/stage1.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/sampling.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

void main() {
  late Fixture fx;
  late FakeSys fake;
  late Stage1 stage;
  late List<(int, int)> ticks;

  setUp(() {
    fx = Fixture();
    fake = FakeSys()
      ..onRun = ffmpegFake
      ..onStart = ffmpegStart;
    stage = Stage1(fx.session.path, fake.sys, stillS: 2);
    ticks = [];
  });

  void progress(int d, int t) => ticks.add((d, t));

  test(
    'a stored frames.json is kept: a resumed job never relabels frames',
    () async {
      // The three jobs the 23:10 shutdown killed were sampled by the old
      // build (a t=0 first frame). Their frames/ and captions are named by
      // index, so the resume must not resample.
      const stored = [
        SampleFrame(t: 0, kind: FrameKind.scene, file: 'f_0001.png'),
        SampleFrame(t: 12, kind: FrameKind.marker, file: 'f_0002.png'),
      ];
      Directory(p.join(fx.session.path, 'analysis', 'frames'))
          .createSync(recursive: true);
      fx.out('frames.json').writeAsStringSync(jsonEncode(stored));
      fx.out('frames/f_0001.png').writeAsStringSync('old black frame');
      final frames = await stage.run(
        durationS: 40,
        markers: [const Marker(wallUnix: 1, offsetS: 12, tag: MarkerTag.good)],
        progress: progress,
      );
      expect(frames.map((f) => (f.t, f.file)), [
        (0.0, 'f_0001.png'),
        (12.0, 'f_0002.png'),
      ]);
      expect(fx.out('frames/f_0001.png').readAsStringSync(), 'old black frame');
      expect(
        fake.of('ffmpeg').where((c) => c.args.join(' ').contains('f_0001.png')),
        isEmpty,
        reason: 'the existing frame is not extracted again',
      );
    },
  );

  test('an empty or garbled frames.json is sampled afresh', () async {
    Directory(p.join(fx.session.path, 'analysis')).createSync();
    for (final junk in ['[]', '{not json', '{"a": 1}']) {
      fx.out('frames.json').writeAsStringSync(junk);
      final frames = await stage.run(
        durationS: 40,
        markers: const [],
        progress: progress,
      );
      expect(frames.first.t, kLeadInS, reason: junk);
    }
  });
}
