/// Stage 2 in batches: [kCaptionBatch] frames per model call, one JSON answer
/// per frame, every answer checked by code.
///
/// A batch the tier cannot answer (rate limit) moves to the next tier whole.
/// A batch answered badly (not JSON, a frame missing or empty) keeps the
/// frames that parsed and captions the missing ones one by one on the same
/// tier. A frame no tier captioned gets a record with no caption: the stage
/// fails closed. The spend of every call lands once, on the first captioned
/// row, so summing rows gives the total.
library;

import 'dart:convert';

import 'package:game_research/core/captions.dart';
import 'package:game_research/core/usage.dart';
import 'package:path/path.dart' as p;

/// Frames per model call.
const kCaptionBatch = 8;

/// A frame to caption: file name, absolute path and time.
class FrameRef {
  /// Creates a reference.
  const new({required this.file, required this.path, required this.t});

  /// File name under `analysis/frames/`.
  final String file;

  /// Where the image is.
  final String path;

  /// Seconds into the recording.
  final double t;
}

/// The prompt for a batch of the image files named in [names].
String batchPrompt(List<String> names) =>
    'You are looking at ${names.length} frames of a video game recording. '
    'For each frame, describe it for a game designer. Reply with ONLY one '
    'JSON array, no prose, no code fence, with exactly one object per frame '
    'in this order: ${names.join(', ')}. Each object is {"frame": "<the file '
    'name>", "screen": "what is on screen", "action": "what the player is '
    'doing", "prompt": "any UI prompt, hint or text shown, verbatim, or an '
    'empty string"}. Each value is one or two plain sentences.';

/// The usable captions in the batch answer [raw], by frame file name in
/// [names]. Objects are matched by their `frame` field; objects without one
/// are positional when the array has exactly one per frame. Invalid objects,
/// unknown frames and repeats are dropped.
Map<String, Caption> parseBatch(String raw, List<String> names) {
  final start = raw.indexOf('[');
  final end = raw.lastIndexOf(']');
  if (start < 0 || end <= start) return {};
  final Object? decoded;
  try {
    decoded = jsonDecode(raw.substring(start, end + 1));
  } on FormatException {
    return {};
  }
  if (decoded is! List) return {};
  final positional = decoded.length == names.length;
  final out = <String, Caption>{};
  for (var i = 0; i < decoded.length; i++) {
    final entry = decoded[i];
    if (entry is! Map) continue;
    final named = entry['frame'];
    final name = named is String
        ? p.basename(named)
        : (positional ? names[i] : null);
    if (name == null || !names.contains(name) || out.containsKey(name)) {
      continue;
    }
    final caption = parseCaption(jsonEncode(entry));
    if (caption != null) out[name] = caption;
  }
  return out;
}

/// Captions [frames] through [tiers] in order; one record per frame, in
/// order, `ok` or not.
Future<List<CaptionRecord>> captionFrames(
  List<CaptionTier> tiers,
  List<FrameRef> frames, {
  String prompt = kCaptionPrompt,
}) async {
  final got = <String, (Caption, String, String?)>{};
  final own = <String, List<String>>{};
  final notes = <String>[];
  final snapshots = <String, List<String>>{};
  var spent = Usage.zero;
  final open = [...frames];

  void accept(FrameRef f, Caption c, CaptionTier tier, String? model) {
    got[f.file] = (c, tier.name, model);
    snapshots[f.file] = [...notes, ...?own[f.file]];
    open.remove(f);
  }

  for (final tier in tiers) {
    if (open.isEmpty) break;
    if (open.length > 1) {
      final TierResult r;
      try {
        r = await tier.captionMany([
          for (final f in open) f.path,
        ], batchPrompt([for (final f in open) f.file]));
      } on Object catch (e) {
        notes.add('${tier.name}: $e');
        continue;
      }
      spent += r.usage;
      if (r.error != null) {
        notes.add('${tier.name}: ${r.error}');
        if (isRateLimited(r.error!)) continue;
      } else {
        final names = [for (final f in open) f.file];
        final parsed = parseBatch(r.text, names);
        for (final f in [...open]) {
          final c = parsed[f.file];
          if (c != null) accept(f, c, tier, r.model);
        }
        if (open.isEmpty) continue;
        final limited = parsed.isEmpty && isRateLimited(r.text);
        notes.add('${tier.name}: ${limited ? 'rate limited' : 'no caption'}');
        if (limited) continue;
      }
    }
    for (final f in [...open]) {
      final TierResult r;
      try {
        r = await tier.caption(f.path, prompt);
      } on Object catch (e) {
        notes.add('${tier.name}: $e');
        break;
      }
      spent += r.usage;
      final error = r.error;
      if (error != null) {
        if (isRateLimited(error)) {
          notes.add('${tier.name}: $error');
          break;
        }
        (own[f.file] ??= []).add('${tier.name}: $error');
        continue;
      }
      final c = parseCaption(r.text);
      if (c != null) {
        accept(f, c, tier, r.model);
        continue;
      }
      if (isRateLimited(r.text)) {
        notes.add('${tier.name}: rate limited');
        break;
      }
      (own[f.file] ??= []).add('${tier.name}: no caption');
    }
  }

  final records = <CaptionRecord>[];
  var carried = spent;
  for (final f in frames) {
    final hit = got[f.file];
    if (hit == null) {
      records.add(
        CaptionRecord(
          frame: f.file,
          t: f.t,
          skipped: [...notes, ...?own[f.file]],
        ),
      );
      continue;
    }
    records.add(
      CaptionRecord(
        frame: f.file,
        t: f.t,
        tier: hit.$2,
        model: hit.$3,
        caption: hit.$1,
        skipped: snapshots[f.file]!,
        usage: carried,
      ),
    );
    carried = Usage.zero;
  }
  return records;
}
