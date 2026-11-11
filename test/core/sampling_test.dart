import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/sampling.dart';

Marker _m(double t, [MarkerTag tag = MarkerTag.good]) =>
    Marker(wallUnix: t, offsetS: t, tag: tag);

void main() {
  group('sampleFrames', () {
    test('keeps every marker, scenes at most one per 10 s', () {
      final frames = sampleFrames(
        scenes: const [0, 3, 9, 10.5, 12, 30],
        markers: [_m(4), _m(4.2, MarkerTag.bad)],
        durationS: 40,
      );
      final scenes = frames.where((f) => f.kind == FrameKind.scene);
      expect(scenes.map((f) => f.t), [0, 10.5, 30]);
      final marks = frames.where((f) => f.kind == FrameKind.marker);
      expect(marks.map((f) => f.t), [4, 4.2]);
      expect(marks.first.tag, MarkerTag.good);
    });

    test('always has a first frame even with no scene cut', () {
      final frames = sampleFrames(scenes: const [], markers: [], durationS: 5);
      expect(frames.single.t, 0);
      expect(frames.single.kind, FrameKind.scene);
    });

    test('frames are in time order and named in that order', () {
      final frames = sampleFrames(
        scenes: const [20, 0],
        markers: [_m(15)],
        durationS: 30,
      );
      expect(frames.map((f) => f.t), [0, 15, 20]);
      expect(frames.map((f) => f.file), [
        'f_0001.png',
        'f_0002.png',
        'f_0003.png',
      ]);
    });

    test('drops scene cuts past the end and clamps marker frames', () {
      final frames = sampleFrames(
        scenes: const [0, 50],
        markers: [_m(12)],
        durationS: 10,
      );
      expect(frames.map((f) => f.t), [0, closeTo(9.9, 1e-9)]);
    });

    test('a custom gap is honoured', () {
      final frames = sampleFrames(
        scenes: const [0, 2, 4, 6],
        markers: [],
        durationS: 10,
        minGapS: 4,
      );
      expect(frames.map((f) => f.t), [0, 4]);
    });
  });

  group('synthesisFrameCap', () {
    test('60 per session hour, rounded up, never below 1', () {
      expect(synthesisFrameCap(3600), 60);
      expect(synthesisFrameCap(5400), 90);
      expect(synthesisFrameCap(10), 1);
      expect(synthesisFrameCap(0), 1);
      expect(synthesisFrameCap(61), 2);
    });
  });

  group('pickSynthesisFrames', () {
    final frames = [
      for (var i = 0; i < 10; i++)
        SampleFrame(t: i * 10.0, kind: FrameKind.scene, file: 's$i.png'),
      const SampleFrame(t: 55, kind: FrameKind.marker, file: 'm1.png'),
      const SampleFrame(t: 95, kind: FrameKind.marker, file: 'm2.png'),
    ];

    test('marker frames first, then scenes spread evenly, time order', () {
      final picked = pickSynthesisFrames(frames, 4);
      expect(picked.map((f) => f.file), [
        's0.png',
        's5.png',
        'm1.png',
        'm2.png',
      ]);
    });

    test('never more than the cap, even with only markers', () {
      expect(pickSynthesisFrames(frames, 1).single.file, 'm1.png');
    });

    test('everything when under the cap', () {
      expect(pickSynthesisFrames(frames, 60), hasLength(12));
    });

    test('a cap of zero picks nothing', () {
      expect(pickSynthesisFrames(frames, 0), isEmpty);
    });
  });

  test('SampleFrame round-trips through json', () {
    const f = SampleFrame(
      t: 4.5,
      kind: FrameKind.marker,
      file: 'f_0001.png',
      tag: MarkerTag.note,
    );
    final back = SampleFrame.fromJson(f.toJson());
    expect(back.t, 4.5);
    expect(back.kind, FrameKind.marker);
    expect(back.tag, MarkerTag.note);
    final scene = SampleFrame.fromJson(
      const SampleFrame(t: 1, kind: FrameKind.scene, file: 'a').toJson(),
    );
    expect(scene.tag, isNull);
  });
}
