import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/captions.dart';

/// A tier that answers from a script and records it was called.
class _Tier implements CaptionTier {
  new(this.name, this.answer);

  @override
  final String name;
  final TierResult Function() answer;
  int calls = 0;

  @override
  Future<TierResult> caption(String imagePath, String prompt) async {
    calls++;
    return answer();
  }

  @override
  Future<TierResult> captionMany(List<String> imagePaths, String prompt) =>
      caption(imagePaths.first, prompt);
}

const _good = '{"screen":"a shelf","action":"placing a book","prompt":""}';

void main() {
  group('parseCaption', () {
    test('reads the JSON object out of surrounding chatter', () {
      final c = parseCaption('Sure!\n```json\n$_good\n```\nD: done');
      expect(c!.screen, 'a shelf');
      expect(c.action, 'placing a book');
      expect(c.uiPrompt, '');
    });

    test('empty screen or action, or no object, is no caption', () {
      expect(parseCaption('{"screen":"","action":"x"}'), isNull);
      expect(parseCaption('{"screen":"x"}'), isNull);
      expect(parseCaption('I cannot see the image'), isNull);
      expect(parseCaption('{broken'), isNull);
      expect(parseCaption('{not json}'), isNull);
      expect(parseCaption('[1, 2]'), isNull);
    });
  });

  group('isRateLimited', () {
    test('spots rate limits and quota notices', () {
      expect(isRateLimited('Error 429 Too Many Requests'), isTrue);
      expect(isRateLimited('Claude AI usage limit reached'), isTrue);
      expect(isRateLimited('rate_limit_error'), isTrue);
      expect(isRateLimited('please top up your balance'), isTrue);
      expect(isRateLimited('a shelf with 429 books'), isFalse);
    });
  });

  group('captionWithFallback', () {
    test('first tier that answers wins; later tiers are not called', () async {
      final a = _Tier('haiku', () => const TierResult.ok(_good, 'haiku'));
      final b = _Tier('omniroute', () => const TierResult.ok(_good, 'x'));
      final rec = await captionWithFallback([a, b], 'f.png', t: 3);
      expect(rec.model, 'haiku');
      expect(rec.tier, 'haiku');
      expect(b.calls, 0);
      expect(rec.ok, isTrue);
      expect(rec.toJson()['frame'], 'f.png');
      expect(rec.toJson()['t'], 3);
    });

    test('skips a failed, rate-limited or empty tier, in order', () async {
      final calls = <String>[];
      TierResult log(String n, TierResult r) {
        calls.add(n);
        return r;
      }

      final tiers = [
        _Tier('haiku', () => log('haiku', const TierResult.fail('exit 1'))),
        _Tier(
          'omniroute',
          () => log('omniroute', const TierResult.ok('429 rate limit', 'm')),
        ),
        _Tier('ollama', () => log('ollama', const TierResult.ok('', 'q'))),
        _Tier('last', () => log('last', const TierResult.ok(_good, 'qwen'))),
      ];
      final rec = await captionWithFallback(tiers, 'f.png', t: 0);
      expect(calls, ['haiku', 'omniroute', 'ollama', 'last']);
      expect(rec.model, 'qwen');
      expect(rec.skipped, [
        'haiku: exit 1',
        'omniroute: rate limited',
        'ollama: no caption',
      ]);
    });

    test('a tier that throws is skipped, not fatal', () async {
      final boom = _Tier('haiku', () => throw StateError('boom'));
      final ok = _Tier('ollama', () => const TierResult.ok(_good, 'qwen'));
      final rec = await captionWithFallback([boom, ok], 'f.png', t: 0);
      expect(rec.model, 'qwen');
      expect(rec.skipped.single, startsWith('haiku: '));
    });

    test('every tier failing fails closed: no caption, no model', () async {
      final rec = await captionWithFallback(
        [_Tier('haiku', () => const TierResult.fail('exit 2'))],
        'f.png',
        t: 1,
      );
      expect(rec.ok, isFalse);
      expect(rec.model, isNull);
      expect(rec.caption, isNull);
    });
  });

  test('CaptionRecord round-trips through json', () {
    final rec = CaptionRecord(
      frame: 'f.png',
      t: 2,
      tier: 'ollama',
      model: 'qwen',
      caption: parseCaption(_good),
      skipped: const ['haiku: exit 1'],
    );
    final back = CaptionRecord.fromJson(rec.toJson());
    expect(back.model, 'qwen');
    expect(back.caption!.action, 'placing a book');
    expect(back.skipped, ['haiku: exit 1']);
    final empty = CaptionRecord.fromJson(const {'frame': 'g.png', 't': 1});
    expect(empty.ok, isFalse);
    expect(empty.skipped, isEmpty);
  });

  test('the caption prompt asks for the three fields as JSON', () {
    expect(kCaptionPrompt, contains('"screen"'));
    expect(kCaptionPrompt, contains('"action"'));
    expect(kCaptionPrompt, contains('"prompt"'));
  });
}
