import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/caption_batch.dart';
import 'package:game_research/core/captions.dart';
import 'package:game_research/core/usage.dart';

String _obj(String name, [String screen = 'a shelf']) =>
    '{"frame":"$name","screen":"$screen","action":"walking","prompt":""}';

const _one = '{"screen":"menu","action":"waiting","prompt":""}';

/// Answers batches and single frames from scripts, counting the calls.
class _Tier implements CaptionTier {
  new(this.name, {this.many, this.single});

  @override
  final String name;
  final TierResult Function(List<String> paths)? many;
  final TierResult Function(String path)? single;
  final manyCalls = <List<String>>[];
  final singleCalls = <String>[];

  @override
  Future<TierResult> caption(String imagePath, String prompt) async {
    singleCalls.add(imagePath);
    return single!(imagePath);
  }

  @override
  Future<TierResult> captionMany(List<String> imagePaths, String prompt) async {
    manyCalls.add(imagePaths);
    return many!(imagePaths);
  }
}

List<FrameRef> _frames(int n) => [
  for (var i = 1; i <= n; i++)
    FrameRef(file: 'f_000$i.png', path: '/a/f_000$i.png', t: i * 10.0),
];

void main() {
  group('parseBatch', () {
    final names = ['f_0001.png', 'f_0002.png'];

    test('maps each object to its frame by name, in any order', () {
      final got = parseBatch(
        'Here you go:\n[${_obj('f_0002.png', 'two')}, '
        "${_obj('f_0001.png', 'one')}]",
        names,
      );
      expect(got['f_0001.png']!.screen, 'one');
      expect(got['f_0002.png']!.screen, 'two');
    });

    test('a path in the frame field still names the file', () {
      final got = parseBatch('[${_obj('/x/f_0001.png')}]', names);
      expect(got.keys, ['f_0001.png']);
    });

    test('objects without a frame field are positional when counts match', () {
      final got = parseBatch('[$_one, $_one]', names);
      expect(got.keys, names);
      expect(parseBatch('[$_one]', names), isEmpty);
    });

    test('invalid objects, unknown frames and duplicates are dropped', () {
      final got = parseBatch(
        '[{"frame":"f_0001.png","screen":"","action":"x"},'
        '${_obj('f_9999.png')}, ${_obj('f_0002.png', 'first')},'
        '${_obj('f_0002.png', 'second')}, 7]',
        names,
      );
      expect(got.keys, ['f_0002.png']);
      expect(got['f_0002.png']!.screen, 'first');
    });

    test('not an array or not json gives nothing', () {
      expect(parseBatch('no idea', names), isEmpty);
      expect(parseBatch('[broken', names), isEmpty);
      expect(parseBatch('{"screen":"x"}', names), isEmpty);
      expect(parseBatch('[not json]', names), isEmpty);
    });
  });

  group('captionFrames', () {
    test(
      'one batch call captions every frame; usage is counted once',
      () async {
        final t = _Tier(
          'haiku',
          many: (paths) => TierResult.ok(
            '[${paths.map((p) => _obj(p.split('/').last)).join(',')}]',
            'claude-haiku',
            const Usage(input: 100, output: 20, costUsd: 0.01),
          ),
        );
        final recs = await captionFrames([t], _frames(3));
        expect(t.manyCalls, hasLength(1));
        expect(t.singleCalls, isEmpty);
        expect(recs.every((r) => r.ok && r.tier == 'haiku'), isTrue);
        expect(recs.map((r) => r.frame), [
          'f_0001.png',
          'f_0002.png',
          'f_0003.png',
        ]);
        expect(recs.map((r) => r.t), [10, 20, 30]);
        expect(recs.first.usage.input, 100);
        expect(recs.skip(1).every((r) => r.usage.isEmpty), isTrue);
      },
    );

    test('a lone frame is a single call, not a batch', () async {
      final t = _Tier('haiku', single: (_) => const TierResult.ok(_one, 'm'));
      final recs = await captionFrames([t], _frames(1));
      expect(t.manyCalls, isEmpty);
      expect(recs.single.ok, isTrue);
    });

    test(
      'a malformed batch falls back to per-frame for the missing ones',
      () async {
        final t = _Tier(
          'haiku',
          many: (paths) => TierResult.ok(
            '[${_obj('f_0001.png')}]',
            'm',
            const Usage(input: 50),
          ),
          single: (_) => const TierResult.ok(_one, 'm', Usage(input: 7)),
        );
        final recs = await captionFrames([t], _frames(3));
        expect(t.manyCalls, hasLength(1));
        expect(t.singleCalls, ['/a/f_0002.png', '/a/f_0003.png']);
        expect(recs.every((r) => r.ok), isTrue);
        expect(recs.first.usage.input, 50 + 7 + 7, reason: 'all spend, once');
      },
    );

    test(
      'a rate-limited batch moves the whole batch to the next tier',
      () async {
        final a = _Tier(
          'haiku',
          many: (_) => const TierResult.fail('usage limit reached'),
        );
        final b = _Tier(
          'omniroute',
          many: (paths) => TierResult.ok(
            '[${paths.map((p) => _obj(p.split('/').last)).join(',')}]',
            'omni',
          ),
        );
        final recs = await captionFrames([a, b], _frames(2));
        expect(a.singleCalls, isEmpty, reason: 'no hammering a limited tier');
        expect(recs.every((r) => r.tier == 'omniroute'), isTrue);
        expect(
          recs.every((r) => r.skipped.single.startsWith('haiku:')),
          isTrue,
          reason: 'every row says why haiku was skipped',
        );
      },
    );

    test(
      'an unusable batch answer then failing singles falls to the next tier',
      () async {
        final a = _Tier(
          'haiku',
          many: (_) => const TierResult.ok('sorry', 'm'),
          single: (_) => const TierResult.fail('exit 1'),
        );
        final b = _Tier(
          'omniroute',
          many: (_) => const TierResult.fail('http 500'),
          single: (_) => const TierResult.ok(_one, 'omni'),
        );
        final recs = await captionFrames([a, b], _frames(2));
        expect(
          a.singleCalls,
          hasLength(2),
          reason: 'a plain error is per frame',
        );
        expect(b.manyCalls, hasLength(1));
        expect(recs.every((r) => r.ok && r.tier == 'omniroute'), isTrue);
        expect(recs.first.skipped.first, contains('haiku: no caption'));
      },
    );

    test('a single answered without a caption is noted on its frame', () async {
      final a = _Tier(
        'haiku',
        many: (_) => const TierResult.ok('[]', 'm'),
        single: (p) => p.endsWith('1.png')
            ? const TierResult.ok('hmm', 'm')
            : const TierResult.ok(_one, 'm'),
      );
      final recs = await captionFrames([a], _frames(2));
      expect(recs.first.ok, isFalse);
      expect(recs.first.skipped.last, 'haiku: no caption');
      expect(recs.last.ok, isTrue);
    });

    test('a rate-limited single stops the tier for the rest', () async {
      final a = _Tier(
        'haiku',
        many: (_) => const TierResult.ok('[]', 'm'),
        single: (_) => const TierResult.ok('rate limit hit', 'm'),
      );
      final recs = await captionFrames([a], _frames(3));
      expect(a.singleCalls, hasLength(1));
      expect(recs.every((r) => !r.ok), isTrue);
      expect(recs.last.skipped.join(), contains('rate limited'));
    });

    test(
      'a thrown tier is a skip, and all tiers failing leaves no caption',
      () async {
        final a = _Tier('haiku', many: (_) => throw StateError('boom'));
        final b = _Tier(
          'ollama',
          many: (_) => const TierResult.fail('down'),
          single: (_) => const TierResult.fail('down'),
        );
        final recs = await captionFrames([a, b], _frames(2));
        expect(recs.every((r) => !r.ok), isTrue);
        expect(recs.first.skipped.first, contains('boom'));
        expect(recs.first.skipped.last, 'ollama: down');
      },
    );

    test('a thrown single call is a skip too', () async {
      final a = _Tier(
        'haiku',
        many: (_) => const TierResult.ok('[]', 'm'),
        single: (_) => throw StateError('kaput'),
      );
      final recs = await captionFrames([a], _frames(2));
      expect(recs.first.skipped.join(), contains('kaput'));
    });

    test('no frames, no calls', () async {
      final t = _Tier('haiku');
      expect(await captionFrames([t], const []), isEmpty);
    });
  });
}
