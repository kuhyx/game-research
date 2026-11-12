import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/tiers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

// Batches and token usage of every real tier (kuhy, 2026-11-12: Haiku took
// 10-14 s per frame, and nothing counted the tokens).
void main() {
  late FakeSys fake;
  late String dir;
  late List<String> images;
  http.Request? seen;

  setUp(() {
    fake = FakeSys();
    final root = tempDir();
    dir = root.path;
    images = ['$dir/f_0001.png', '$dir/f_0002.png'];
    for (final i in images) {
      File(i).writeAsBytesSync([1, 2, 3]);
    }
    seen = null;
  });

  const claude = {
    'type': 'result',
    'subtype': 'success',
    'is_error': false,
    'result': '[]',
    'usage': {
      'input_tokens': 11,
      'output_tokens': 22,
      'cache_read_input_tokens': 33,
      'cache_creation_input_tokens': 44,
    },
    'total_cost_usd': 0.07,
  };

  group('ClaudeTier', () {
    test('a single caption reports the envelope usage', () async {
      final config = testConfig(tempDir());
      fake.onRun = (_) => ok(jsonEncode(claude));
      final r = await ClaudeTier(
        config,
        fake.sys,
        model: 'haiku',
      ).caption(images.first, 'p');
      expect(r.usage.input, 11);
      expect(r.usage.cacheWrite, 44);
      expect(r.usage.costUsd, 0.07);
    });

    test('captionMany names every file and reads them all', () async {
      final config = testConfig(tempDir());
      fake.onRun = (_) => ok(jsonEncode(claude));
      final r = await ClaudeTier(
        config,
        fake.sys,
        model: 'haiku',
      ).captionMany(images, 'the batch prompt');
      expect(r.error, isNull);
      final call = fake.calls.single;
      final prompt = call.args[call.args.indexOf('-p') + 1];
      expect(prompt, contains('the batch prompt'));
      for (final i in images) {
        expect(prompt, contains(i));
      }
      expect(call.args.take(1), ['300'], reason: 'a batch gets a longer limit');
      expect(call.cwd, dir);
    });

    test('a failed envelope still reports what it cost', () async {
      final config = testConfig(tempDir());
      fake.onRun = (_) => ok(
        jsonEncode({
          ...claude,
          'is_error': true,
          'result': 'Claude AI usage limit reached',
        }),
      );
      final r = await ClaudeTier(
        config,
        fake.sys,
        model: 'haiku',
      ).captionMany(images, 'p');
      expect(r.error, contains('usage limit'));
      expect(r.usage.output, 22);
    });
  });

  group('FakeTier', () {
    test('captionMany passes every file to the executable', () async {
      final config = testConfig(
        tempDir(),
        extra: {'GAME_RESEARCH_FAKE_LLM': '/fake/llm'},
      );
      fake.onRun = (_) => ok('[]');
      final r = await FakeTier(
        config,
        fake.sys,
        'omniroute',
      ).captionMany(images, 'p');
      expect(r.text, '[]');
      expect(fake.calls.single.args, ['omniroute', ...images]);
    });
  });

  group('HttpTier', () {
    http.Client client(Object body) => MockClient((r) async {
      seen = r;
      return http.Response(jsonEncode(body), 200);
    });

    test('OmniRoute: all images in one request, usage from the body', () async {
      final config = testConfig(tempDir());
      File(config.omniKeyFile)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('k');
      final r = await HttpTier.omniroute(
        config,
        client({
          'model': 'm',
          'choices': [
            {
              'message': {'content': '[]'},
            },
          ],
          'usage': {
            'prompt_tokens': 5,
            'completion_tokens': 6,
            'prompt_tokens_details': {'cached_tokens': 2},
          },
        }),
      ).captionMany(images, 'p');
      expect(r.text, '[]');
      expect((r.usage.input, r.usage.output, r.usage.cacheRead), (5, 6, 2));
      final messages =
          (jsonDecode(seen!.body) as Map<String, Object?>)['messages']!
              as List<Object?>;
      final content =
          (messages.single! as Map<String, Object?>)['content']!
              as List<Object?>;
      expect(
        content.where(
          (c) => (c! as Map<String, Object?>)['type'] == 'image_url',
        ),
        hasLength(2),
      );
    });

    test('ollama: all images in one message, counts from the body', () async {
      final config = testConfig(tempDir());
      final r = await HttpTier.ollama(
        config,
        client({
          'message': {'content': '[]'},
          'prompt_eval_count': 40,
          'eval_count': 9,
        }),
      ).captionMany(images, 'p');
      expect((r.usage.input, r.usage.output), (40, 9));
      final msg =
          ((jsonDecode(seen!.body) as Map)['messages'] as List).single as Map;
      expect(msg['images'], hasLength(2));
    });
  });
}
