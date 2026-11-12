/// The real caption tiers and the synthesis call.
///
/// 1. Claude Haiku through `claude -p` on kuhy's subscription: Read is its
///    only tool, hooks off, the envelope decides success.
/// 2. OmniRoute's free vision model over its OpenAI API (bearer key read
///    from `~/.config/omniroute/api_key` per call, never logged).
/// 3. Local ollama with qwen3-vl.
/// `GAME_RESEARCH_FAKE_LLM` replaces every model with one executable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/captions.dart';
import 'package:game_research/core/claude_envelope.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

String _clip(Object? text) {
  final s = '$text'.trim().replaceAll('\n', ' ');
  return s.length > 160 ? s.substring(0, 160) : s;
}

/// `claude -p` with Read only, as a caption tier or for the synthesis.
class ClaudeTier implements CaptionTier {
  /// Creates a tier for [model] (`haiku`, `opus`).
  const new(this.config, this.sys, {required this.model, this.limitS = 180});

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  /// Model alias.
  final String model;

  /// Seconds before `timeout` kills the call.
  final int limitS;

  @override
  String get name => model;

  /// Runs [prompt], letting Claude read files under [readDirs].
  Future<TierResult> ask(String prompt, List<String> readDirs) async {
    final r = await sys.run('timeout', [
      '$limitS',
      config.claudeBin,
      '-p',
      prompt,
      '--model',
      model,
      '--output-format',
      'json',
      '--tools',
      'Read',
      '--allowedTools',
      'Read',
      for (final d in readDirs) ...['--add-dir', d],
      '--no-session-persistence',
      '--settings',
      '{"disableAllHooks":true}',
    ], workingDirectory: readDirs.first);
    final answer = readClaudeEnvelope('${r.stdout}');
    if (r.exitCode != 0 && !answer.ok) {
      return TierResult.fail('exit ${r.exitCode}: ${_clip(answer.reason)}');
    }
    if (!answer.ok) return TierResult.fail(_clip(answer.reason));
    return TierResult.ok(answer.text, answer.model ?? 'claude-$model');
  }

  @override
  Future<TierResult> caption(String imagePath, String prompt) => ask(
    '$prompt\nThe frame is the image file $imagePath; read it with the '
    'Read tool.',
    [p.dirname(imagePath)],
  );
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
  Future<TierResult> caption(String imagePath, String prompt) async {
    final b64 = base64Encode(File(imagePath).readAsBytesSync());
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
          {
            'role': 'user',
            'content': prompt,
            'images': [b64],
          },
        ],
      };
    } else {
      final keyFile = File(config.omniKeyFile);
      if (!keyFile.existsSync()) return const TierResult.fail('no api key');
      headers['Authorization'] = 'Bearer ${keyFile.readAsStringSync().trim()}';
      url = Uri.parse('${config.omniUrl}/v1/chat/completions');
      body = {
        'model': config.omniModel,
        'max_tokens': 1000,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,$b64'},
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
          .timeout(Duration(seconds: _ollama ? 240 : 120));
    } on Exception catch (e) {
      return TierResult.fail(_clip(e));
    }
    if (res.statusCode != 200) {
      return TierResult.fail('http ${res.statusCode}: ${_clip(res.body)}');
    }
    final Object? json;
    try {
      json = jsonDecode(res.body);
    } on FormatException {
      return TierResult.fail('not json: ${_clip(res.body)}');
    }
    if (json is! Map) {
      return TierResult.fail('not an object: ${_clip(res.body)}');
    }
    if (_ollama) {
      final text = (json['message'] as Map?)?['content'];
      return TierResult.ok('${text ?? ''}', 'ollama/${config.ollamaModel}');
    }
    final choices = json['choices'];
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    final text = first is Map ? ((first['message'] as Map?)?['content']) : null;
    return TierResult.ok(
      '${text ?? ''}',
      'omniroute/${json['model'] ?? config.omniModel}',
    );
  }
}

/// Every model replaced by one executable: `<exe> <tier> <file>`, stdout is
/// the answer (tests and the E2E).
class FakeTier implements CaptionTier {
  /// Creates the fake [name] tier.
  const new(this.config, this.sys, this.name);

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  @override
  final String name;

  /// Runs the fake on [file].
  Future<TierResult> call(String file) async {
    final r = await sys.run(config.fakeLlm, [name, file]);
    if (r.exitCode != 0) {
      final why = _clip(r.stderr);
      return TierResult.fail(
        'exit ${r.exitCode}${why.isEmpty ? '' : ': $why'}',
      );
    }
    return TierResult.ok('${r.stdout}', 'fake:$name');
  }

  @override
  Future<TierResult> caption(String imagePath, String prompt) =>
      call(imagePath);
}

/// The caption chain in order: haiku, OmniRoute, ollama.
List<CaptionTier> captionTiers(Config config, Sys sys, http.Client client) {
  if (config.fakeLlm.isNotEmpty) {
    return [
      for (final n in const ['haiku', 'omniroute', 'ollama'])
        FakeTier(config, sys, n),
    ];
  }
  return [
    ClaudeTier(config, sys, model: 'haiku'),
    HttpTier.omniroute(config, client),
    HttpTier.ollama(config, client),
  ];
}
