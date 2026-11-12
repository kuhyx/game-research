/// The two caption tiers behind an HTTP API: OmniRoute's free vision model
/// (OpenAI chat API, bearer key read from `~/.config/omniroute/api_key` per
/// call, never logged) and local ollama with qwen3-vl.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/captions.dart';
import 'package:game_research/core/usage.dart';
import 'package:game_research/desktop/config.dart';
import 'package:http/http.dart' as http;

/// [text] on one line, at most 160 characters: a failure reason.
String clipReason(Object? text) {
  final s = '$text'.trim().replaceAll('\n', ' ');
  return s.length > 160 ? s.substring(0, 160) : s;
}

/// A vision model behind an HTTP API (OmniRoute or ollama).
class HttpTier implements CaptionTier {
  /// OmniRoute's OpenAI-compatible chat API.
  new omniroute(this.config, this.client) : name = 'omniroute', _ollama = false;

  /// ollama's chat API.
  new ollama(this.config, this.client) : name = 'ollama', _ollama = true;

  /// Settings.
  final Config config;

  /// HTTP client.
  final http.Client client;
  final bool _ollama;

  @override
  final String name;

  @override
  Future<TierResult> caption(String imagePath, String prompt) =>
      _call([imagePath], prompt);

  @override
  Future<TierResult> captionMany(List<String> imagePaths, String prompt) =>
      _call(imagePaths, prompt);

  Future<TierResult> _call(List<String> images, String prompt) async {
    final b64 = [
      for (final i in images) base64Encode(File(i).readAsBytesSync()),
    ];
    final Uri url;
    final headers = <String, String>{'Content-Type': 'application/json'};
    final Object body;
    if (_ollama) {
      url = Uri.parse('${config.ollamaUrl}/api/chat');
      body = {
        'model': config.ollamaModel,
        'stream': false,
        'options': {'temperature': 0},
        'messages': [
          {'role': 'user', 'content': prompt, 'images': b64},
        ],
      };
    } else {
      final keyFile = File(config.omniKeyFile);
      if (!keyFile.existsSync()) return const TierResult.fail('no api key');
      headers['Authorization'] = 'Bearer ${keyFile.readAsStringSync().trim()}';
      url = Uri.parse('${config.omniUrl}/v1/chat/completions');
      body = {
        'model': config.omniModel,
        'max_tokens': 1000 * images.length,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              for (final b in b64)
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/png;base64,$b'},
                },
            ],
          },
        ],
      };
    }
    final http.Response res;
    try {
      res = await client
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(Duration(seconds: (_ollama ? 240 : 120) * images.length));
    } on Exception catch (e) {
      return TierResult.fail(clipReason(e));
    }
    if (res.statusCode != 200) {
      return TierResult.fail('http ${res.statusCode}: ${clipReason(res.body)}');
    }
    final Object? json;
    try {
      json = jsonDecode(res.body);
    } on FormatException {
      return TierResult.fail('not json: ${clipReason(res.body)}');
    }
    if (json is! Map) {
      return TierResult.fail('not an object: ${clipReason(res.body)}');
    }
    if (_ollama) {
      final text = (json['message'] as Map?)?['content'];
      return TierResult.ok(
        '${text ?? ''}',
        'ollama/${config.ollamaModel}',
        Usage.fromOllama(json),
      );
    }
    final choices = json['choices'];
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    final text = first is Map ? ((first['message'] as Map?)?['content']) : null;
    return TierResult.ok(
      '${text ?? ''}',
      'omniroute/${json['model'] ?? config.omniModel}',
      Usage.fromOpenAi(json),
    );
  }
}
