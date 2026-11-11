/// Stage 2's caption fallback chain, independent of how a tier is reached.
///
/// Tiers are tried in order per frame (haiku, OmniRoute, ollama). A tier is
/// skipped when it fails (non-zero exit, HTTP error, exception), reports a
/// rate limit or answers without a usable caption. A frame no tier could
/// caption gets a record with no model: the stage then fails closed.
library;

import 'dart:convert';

/// What every tier is asked, per frame.
const kCaptionPrompt =
    'You are looking at one frame of a video game recording. Describe it '
    'for a game designer. Reply with ONLY one JSON object, no prose, no code '
    'fence: {"screen": "what is on screen", "action": "what the player is '
    'doing", "prompt": "any UI prompt, hint or text shown, verbatim, or an '
    'empty string"}. Each value is one or two plain sentences.';

/// A tier's raw answer.
class TierResult {
  /// An answer [text] from [model].
  const new ok(this.text, this.model) : error = null;

  /// A failure, with why.
  const new fail(String this.error) : text = '', model = null;

  /// The answer text ('' on failure).
  final String text;

  /// Which model answered (null on failure).
  final String? model;

  /// Why it failed (null on success).
  final String? error;
}

/// One way of captioning a frame.
abstract interface class CaptionTier {
  /// Short tier name (`haiku`, `omniroute`, `ollama`).
  String get name;

  /// Captions the image at [imagePath] with [prompt].
  Future<TierResult> caption(String imagePath, String prompt);
}

/// A parsed caption.
class Caption {
  /// Creates a caption.
  const new({
    required this.screen,
    required this.action,
    required this.uiPrompt,
  });

  /// What is on screen.
  final String screen;

  /// What the player is doing.
  final String action;

  /// Any UI prompt shown ('' for none).
  final String uiPrompt;

  /// The caption's JSON object.
  Map<String, Object?> toJson() => {
    'screen': screen,
    'action': action,
    'prompt': uiPrompt,
  };
}

/// The first `{...}` object in [raw] holding a non-empty screen and action,
/// or null. Models wrap JSON in prose or fences; only the object counts.
Caption? parseCaption(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final screen = '${decoded['screen'] ?? ''}'.trim();
  final action = '${decoded['action'] ?? ''}'.trim();
  if (screen.isEmpty || action.isEmpty) return null;
  return Caption(
    screen: screen,
    action: action,
    uiPrompt: '${decoded['prompt'] ?? ''}'.trim(),
  );
}

// A bare "429" only counts as an HTTP status: after error/status/http or at
// the very start, never as a number inside prose.
final _rateLimit = RegExp(
  'rate.?limit|usage limit|too many requests|quota|top.?up|cooling down|'
  r'\b(error|status|http)\s*:?\s*429\b|^\s*429\b',
  caseSensitive: false,
);

/// Whether [text] is a rate-limit or quota notice rather than an answer.
bool isRateLimited(String text) => _rateLimit.hasMatch(text);

/// One `captions.jsonl` line.
class CaptionRecord {
  /// Creates a record; [caption] null means no tier answered.
  const new({
    required this.frame,
    required this.t,
    this.tier,
    this.model,
    this.caption,
    this.skipped = const [],
  });

  /// Reads one decoded line.
  factory fromJson(Map<String, Object?> json) {
    final c = json['caption'];
    return CaptionRecord(
      frame: json['frame']! as String,
      t: (json['t']! as num).toDouble(),
      tier: json['tier'] as String?,
      model: json['model'] as String?,
      caption: c is Map ? parseCaption(jsonEncode(c)) : null,
      skipped: [...?(json['skipped'] as List?)?.cast<String>()],
    );
  }

  /// Frame file name.
  final String frame;

  /// Seconds into the recording.
  final double t;

  /// Tier that answered.
  final String? tier;

  /// Model that answered.
  final String? model;

  /// The caption, or null when every tier failed.
  final Caption? caption;

  /// `tier: why` for each tier skipped before the answer.
  final List<String> skipped;

  /// Whether a tier captioned the frame.
  bool get ok => caption != null;

  /// The line's JSON object.
  Map<String, Object?> toJson() => {
    'frame': frame,
    't': t,
    'tier': tier,
    'model': model,
    'caption': caption?.toJson(),
    'skipped': skipped,
  };
}

/// Tries [tiers] in order on [frame]; the first usable caption wins.
Future<CaptionRecord> captionWithFallback(
  List<CaptionTier> tiers,
  String frame, {
  required double t,
  String prompt = kCaptionPrompt,
}) async {
  final skipped = <String>[];
  for (final tier in tiers) {
    final TierResult result;
    try {
      result = await tier.caption(frame, prompt);
    } on Object catch (error) {
      skipped.add('${tier.name}: $error');
      continue;
    }
    // A usable caption wins even if it happens to mention a quota; only an
    // answer without one is classified as a rate limit or an empty answer.
    final caption = result.error == null ? parseCaption(result.text) : null;
    if (result.error != null) {
      skipped.add('${tier.name}: ${result.error}');
    } else if (caption == null) {
      final why = isRateLimited(result.text) ? 'rate limited' : 'no caption';
      skipped.add('${tier.name}: $why');
    } else {
      return CaptionRecord(
        frame: frame,
        t: t,
        tier: tier.name,
        model: result.model,
        caption: caption,
        skipped: skipped,
      );
    }
  }
  return CaptionRecord(frame: frame, t: t, skipped: skipped);
}
