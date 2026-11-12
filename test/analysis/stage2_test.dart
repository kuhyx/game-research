import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/stage2.dart';
import 'package:game_research/core/captions.dart';
import 'package:game_research/core/sampling.dart';
import 'package:game_research/core/usage.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';

/// Answers single frames from [answer] and batches from [many] (default: a
/// plain failure, so the chain falls back to single frames).
class ScriptedTier implements CaptionTier {
  new(this.name, this.answer, {this.many});

  @override
  final String name;
  final TierResult Function(String path) answer;
  final TierResult Function(List<String> paths)? many;
  final seen = <String>[];
  final batches = <List<String>>[];

  @override
  Future<TierResult> caption(String imagePath, String prompt) async {
    seen.add(p.basename(imagePath));
    return answer(imagePath);
  }

  @override
  Future<TierResult> captionMany(List<String> imagePaths, String prompt) async {
    batches.add([for (final i in imagePaths) p.basename(i)]);
    return many?.call(imagePaths) ?? const TierResult.fail('no batch');
  }
}

TierResult _array(List<String> paths) => TierResult.ok(
  jsonEncode([
    for (final path in paths)
      {
        'frame': p.basename(path),
        'screen': 'menu',
        'action': 'waiting',
        'prompt': '',
      },
  ]),
  'm',
  const Usage(input: 9, output: 3),
);

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

  test(
    'a torn caption line is not captioned and the file is repaired',
    () async {
      final row = jsonEncode({'frame': 'f_0001.png', 't': 0});
      final path = fx.out('captions.jsonl')
        ..writeAsStringSync(
          '$row\n${jsonEncode({'frame': 'f_0002.png', 't': 5})}\n'
          '{"frame":"f_0003.png","t":9,"cap\x00\x00\x00',
        );
      final stage = Stage2(fx.session.path, [
        ScriptedTier('t1', (_) => const TierResult.ok(kCaptionJson, 'm')),
      ]);
      expect(stage.done(), {'f_0001.png', 'f_0002.png'});
      expect(stage.repair(), 1);
      expect(path.readAsStringSync().split('\n').where((l) => l.isNotEmpty), [
        row,
        jsonEncode({'frame': 'f_0002.png', 't': 5}),
      ]);
      expect(File('${path.path}.tmp').existsSync(), isFalse);
      expect(stage.repair(), 0, reason: 'a clean file is left alone');
      await stage.run(frames, (_, _) {});
      final lines = path.readAsLinesSync();
      expect(lines, hasLength(3), reason: 'the torn frame is captioned again');
      for (final l in lines) {
        expect(jsonDecode(l), isA<Map<String, Object?>>());
      }
      expect(lines.last, contains('f_0003.png'));
    },
  );

  test('a row without a frame counts as torn', () {
    fx.out('captions.jsonl').writeAsStringSync('{"t":1}\n');
    final stage = Stage2(fx.session.path, const []);
    expect(stage.done(), isEmpty);
    expect(stage.repair(), 1);
  });

  test('one batch call captions the frames, one line each', () async {
    final good = ScriptedTier(
      't1',
      (_) => const TierResult.ok(kCaptionJson, 'm'),
      many: _array,
    );
    final ticks = <(int, int)>[];
    final failed = await Stage2(fx.session.path, [
      good,
    ]).run(frames, (d, t) => ticks.add((d, t)));
    expect(failed, isEmpty);
    expect(good.batches, [
      ['f_0001.png', 'f_0002.png', 'f_0003.png'],
    ]);
    expect(good.seen, isEmpty);
    expect(ticks.last, (3, 3));
    final lines = fx.out('captions.jsonl').readAsLinesSync();
    expect(lines, hasLength(3));
    final first = jsonDecode(lines.first) as Map<String, Object?>;
    expect(first, containsPair('frame', 'f_0001.png'));
    expect(first, containsPair('tier', 't1'));
    expect((first['usage']! as Map)['in'], 9, reason: 'usage on the first row');
    expect(jsonDecode(lines.last), isNot(contains('usage')));
  });

  test('batches hold at most 8 frames', () async {
    final many = [
      for (var i = 1; i <= 10; i++)
        SampleFrame(
          t: i * 10,
          kind: FrameKind.scene,
          file: 'f_${i.toString().padLeft(4, '0')}.png',
        ),
    ];
    final good = ScriptedTier(
      't1',
      (_) => const TierResult.ok(kCaptionJson, 'm'),
      many: _array,
    );
    final ticks = <int>[];
    await Stage2(fx.session.path, [good]).run(many, (d, _) => ticks.add(d));
    expect(good.batches.map((b) => b.length), [8, 2]);
    expect(ticks.last, 10);
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
    final ticks = <int>[];
    await Stage2(fx.session.path, [good]).run(frames, (d, _) => ticks.add(d));
    expect(good.seen, ['f_0002.png']);
    expect(good.batches, isEmpty, reason: 'one frame left is not a batch');
    expect(fx.out('captions.jsonl').readAsLinesSync(), hasLength(3));
    expect(ticks.last, 3, reason: 'counts the frames already done');
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
      expect(failed, hasLength(1));
      expect(failed.single, startsWith('f_0002.png ('));
      expect(failed.single, contains('t2: boom'));
      expect(fx.out('captions.jsonl').readAsLinesSync(), hasLength(2));
    },
  );

  test('the stage stops after a batch that left a frame uncaptioned', () async {
    final all = [
      for (var i = 1; i <= 10; i++)
        SampleFrame(
          t: i * 10,
          kind: FrameKind.scene,
          file: 'f_${i.toString().padLeft(4, '0')}.png',
        ),
    ];
    final limited = ScriptedTier(
      't1',
      (_) => const TierResult.fail('usage limit'),
      many: (_) => const TierResult.fail('usage limit'),
    );
    final failed = await Stage2(fx.session.path, [limited]).run(all, (_, _) {});
    expect(failed, hasLength(8));
    expect(limited.batches, hasLength(1), reason: 'no second batch');
  });
}
