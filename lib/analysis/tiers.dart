/// The real caption tiers and the synthesis call.
///
/// 1. Claude Haiku through `claude -p` on kuhy's subscription: Read is its
///    only tool, hooks off, the envelope decides success.
/// 2. OmniRoute's free vision model over its OpenAI API ([HttpTier]).
/// 3. Local ollama with qwen3-vl ([HttpTier]).
/// Every tier answers a batch of frames in one call and reports its usage.
/// `GAME_RESEARCH_FAKE_LLM` replaces every model with one executable.
library;

import 'package:game_research/analysis/http_tier.dart';
import 'package:game_research/core/captions.dart';
import 'package:game_research/core/claude_envelope.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

export 'package:game_research/analysis/http_tier.dart';

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

  /// Runs [prompt], letting Claude read files under [readDirs]; [limit]
  /// overrides [limitS].
  Future<TierResult> ask(
    String prompt,
    List<String> readDirs, {
    int? limit,
  }) async {
    final r = await sys.run('timeout', [
      '${limit ?? limitS}',
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
      return TierResult.fail(
        'exit ${r.exitCode}: ${clipReason(answer.reason)}',
        answer.usage,
      );
    }
    if (!answer.ok) {
      return TierResult.fail(clipReason(answer.reason), answer.usage);
    }
    return TierResult.ok(
      answer.text,
      answer.model ?? 'claude-$model',
      answer.usage,
    );
  }

  @override
  Future<TierResult> caption(String imagePath, String prompt) => ask(
    '$prompt\nThe frame is the image file $imagePath; read it with the '
    'Read tool.',
    [p.dirname(imagePath)],
  );

  @override
  Future<TierResult> captionMany(List<String> imagePaths, String prompt) => ask(
    '$prompt\nThe frames are these image files, in this order; read each '
    'with the Read tool:\n${imagePaths.join('\n')}',
    [p.dirname(imagePaths.first)],
    limit: limitS > 300 ? limitS : 300,
  );
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

  /// Runs the fake on [file] and [more] (one frame, or a whole batch).
  Future<TierResult> call(String file, [List<String> more = const []]) async {
    final r = await sys.run(config.fakeLlm, [name, file, ...more]);
    if (r.exitCode != 0) {
      final why = clipReason(r.stderr);
      return TierResult.fail(
        'exit ${r.exitCode}${why.isEmpty ? '' : ': $why'}',
      );
    }
    return TierResult.ok('${r.stdout}', 'fake:$name');
  }

  @override
  Future<TierResult> caption(String imagePath, String prompt) =>
      call(imagePath);

  @override
  Future<TierResult> captionMany(List<String> imagePaths, String prompt) =>
      call(imagePaths.first, imagePaths.skip(1).toList());
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
