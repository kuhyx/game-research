import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/tiers.dart';
import 'package:game_research/desktop/config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

void main() {
  late Config config;
  late String image;
  http.Request? seen;

  http.Client client(http.Response Function(http.Request) answer) =>
      MockClient((r) async {
        seen = r;
        return answer(r);
      });

  setUp(() {
    final root = tempDir();
    config = testConfig(root);
    image = '${root.path}/f.png';
    File(image).writeAsBytesSync([1, 2, 3]);
    seen = null;
  });

  void writeKey([String key = ' secret-key\n']) {
    File(config.omniKeyFile)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(key);
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  group('OmniRoute', () {
    HttpTier tier(http.Client c) => HttpTier.omniroute(config, c);

    test('named omniroute', () {
      expect(tier(client((_) => json({}))).name, 'omniroute');
    });

    test('no key file means no call', () async {
      final r = await tier(client((_) => json({}))).caption(image, 'p');
      expect(r.error, 'no api key');
      expect(seen, isNull);
    });

    test('posts the frame with the bearer key, reads the answer', () async {
      writeKey();
      final t = tier(
        client(
          (_) => json({
            'model': 'agnes/real',
            'choices': [
              {
                'message': {'content': kCaptionJson},
              },
            ],
          }),
        ),
      );
      final r = await t.caption(image, 'describe');
      expect(r.text, kCaptionJson);
      expect(r.model, 'omniroute/agnes/real');
      expect(seen!.url.toString(), '${config.omniUrl}/v1/chat/completions');
      expect(seen!.headers['Authorization'], 'Bearer secret-key');
      final body = jsonDecode(seen!.body) as Map<String, Object?>;
      expect(body['model'], config.omniModel);
      expect('${body['messages']}', contains(base64Encode([1, 2, 3])));
    });

    test('a shapeless answer is ok but empty, default model', () async {
      writeKey();
      for (final body in <Object>[
        {'choices': <Object>[]},
        {
          'choices': ['x'],
        },
        {
          'choices': [
            {'message': <String, Object>{}},
          ],
        },
        <String, Object>{},
      ]) {
        final r = await tier(client((_) => json(body))).caption(image, 'p');
        expect(r.error, isNull);
        expect(r.text, '');
        expect(r.model, 'omniroute/${config.omniModel}');
      }
    });

    test('non-200, bad json and a non-object fail with the reason', () async {
      writeKey();
      var r = await tier(client((_) => http.Response('quota\nhit', 429)))
          .caption(image, 'p');
      expect(r.error, 'http 429: quota hit');
      r = await tier(client((_) => http.Response('<html>', 200)))
          .caption(image, 'p');
      expect(r.error, 'not json: <html>');
      r = await tier(client((_) => json([1]))).caption(image, 'p');
      expect(r.error, 'not an object: [1]');
    });

    test('a throwing or timing-out client fails the tier only', () async {
      writeKey();
      var r = await tier(
        MockClient((_) async => throw const SocketException('refused')),
      ).caption(image, 'p');
      expect(r.error, contains('refused'));
      r = await tier(MockClient((_) async => throw TimeoutException('slow')))
          .caption(image, 'p');
      expect(r.error, contains('slow'));
    });
  });

  group('ollama', () {
    HttpTier tier(http.Client c) => HttpTier.ollama(config, c);

    test('posts to /api/chat without a key', () async {
      final t = tier(
        client(
          (_) => json({
            'message': {'content': kCaptionJson},
          }),
        ),
      );
      expect(t.name, 'ollama');
      final r = await t.caption(image, 'describe');
      expect(r.text, kCaptionJson);
      expect(r.model, 'ollama/${config.ollamaModel}');
      expect(seen!.url.toString(), '${config.ollamaUrl}/api/chat');
      expect(seen!.headers.containsKey('Authorization'), isFalse);
      final body = jsonDecode(seen!.body) as Map<String, Object?>;
      expect(body['stream'], false);
    });

    test('a missing message is an empty answer; errors fail', () async {
      final empty = await tier(client((_) => json({}))).caption(image, 'p');
      expect(empty.text, '');
      final r = await tier(client((_) => http.Response('down', 503)))
          .caption(image, 'p');
      expect(r.error, 'http 503: down');
    });
  });

  group('FakeTier and the chain', () {
    Config fakeLlm() =>
        testConfig(tempDir(), extra: {'GAME_RESEARCH_FAKE_LLM': '/f'});

    test('FakeTier runs the executable on the file', () async {
      final fake = FakeSys()..onRun = (_) => ok('caption text');
      final cfg = fakeLlm();
      final r = await FakeTier(cfg, fake.sys, 'haiku').caption(image, 'p');
      expect(r.text, 'caption text');
      expect(r.model, 'fake:haiku');
      expect(fake.calls.single.line, '/f haiku $image');
      fake.onRun = (_) => bad('', 3);
      expect((await FakeTier(cfg, fake.sys, 'x').call('f')).error, 'exit 3');
    });

    test('captionTiers: fakes when configured, else the real three', () {
      final fake = FakeSys();
      final http = MockClient((_) async => json({}));
      final plain = captionTiers(config, fake.sys, http);
      expect(plain.map((t) => t.name), ['haiku', 'omniroute', 'ollama']);
      expect(plain.first, isA<ClaudeTier>());
      final fakes = captionTiers(fakeLlm(), fake.sys, http);
      expect(fakes.map((t) => t.name), ['haiku', 'omniroute', 'ollama']);
      expect(fakes, everyElement(isA<FakeTier>()));
    });
  });
}
