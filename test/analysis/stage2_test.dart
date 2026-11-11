import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/stage2.dart';
import 'package:game_research/core/captions.dart';
import 'package:game_research/core/sampling.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';

class ScriptedTier implements CaptionTier {
  new(this.name, this.answer);

  @override
  final String name;
  final TierResult Function(String path) answer;
  final seen = <String>[];

  @override
  Future<TierResult> caption(String imagePath, String prompt) async {
    seen.add(p.basename(imagePath));
    return answer(imagePath);
  }
}

const frames = [
  SampleFrame(t: 0, kind: FrameKind.scene, file: 'f_0001.png'),
  SampleFrame(t: 5, kind: FrameKind.scene, file: 'f_0002.png'),
  SampleFrame(t: 9, kind: FrameKind.scene, file: 'f_0003.png'),
];

void main() {
  late Fixture fx;

  setUp(() {
    fx = Fixture();
    Directory(p.join(fx.session.path, 'analysis')).createSync();
  });

  test('done is empty without a captions file, skips blank lines', () {
    final stage = Stage2(fx.session.path, const []);
    expect(stage.done(), isEmpty);
    fx
        .out('captions.jsonl')
        .writeAsStringSync(
          '${jsonEncode({'frame': 'f_0001.png', 't': 0})}\n\n',
        );
    expect(stage.done(), {'f_0001.png'});
  });

  test('captions every frame once and appends a line each', () async {
    final good = ScriptedTier(
      't1',
      (_) => const TierResult.ok(kCaptionJson, 'm'),
    );
    final ticks = <int>[];
    final failed = await Stage2(fx.session.path, [
      good,
    ]).run(frames, (d, t) => ticks.add(d));
    expect(failed, isEmpty);
    expect(ticks, [1, 2, 3]);
    final lines = fx.out('captions.jsonl').readAsLinesSync();
    expect(lines, hasLength(3));
    expect(jsonDecode(lines.first), containsPair('frame', 'f_0001.png'));
    expect(jsonDecode(lines.first), containsPair('tier', 't1'));
  });

  test('a rerun captions only the missing frames', () async {
    fx
        .out('captions.jsonl')
        .writeAsStringSync(
          '${jsonEncode({'frame': 'f_0001.png', 't': 0})}\n'
          '${jsonEncode({'frame': 'f_0003.png', 't': 9})}\n',
        );
    final good = ScriptedTier(
      't1',
      (_) => const TierResult.ok(kCaptionJson, 'm'),
    );
    await Stage2(fx.session.path, [good]).run(frames, (_, _) {});
    expect(good.seen, ['f_0002.png']);
    expect(fx.out('captions.jsonl').readAsLinesSync(), hasLength(3));
  });

  test(
    'the next tier takes over; a frame nobody captions is returned',
    () async {
      final down = ScriptedTier('t1', (_) => const TierResult.fail('rate'));
      final some = ScriptedTier(
        't2',
        (path) => path.endsWith('f_0002.png')
            ? const TierResult.fail('boom')
            : const TierResult.ok(kCaptionJson, 'm'),
      );
      final failed = await Stage2(fx.session.path, [
        down,
        some,
      ]).run(frames, (_, _) {});
      expect(failed, ['f_0002.png (t1: rate; t2: boom)']);
      expect(fx.out('captions.jsonl').readAsLinesSync(), hasLength(2));
    },
  );
}
