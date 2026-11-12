/// Which frames stage 1 extracts, and which of those stage 3 shows Opus.
///
/// Stage 1: every marker gets a frame; scene cuts get one at most every
/// [kSceneGapS] seconds. The recording opens on a black lead-in, so the first
/// scene frame is taken at [kLeadInS] and no scene frame earlier. Stage 3: at
/// most [kSynthesisFramesPerHour] frames per session hour, rounded up and
/// never below one, marker frames first. Stage 2 captions only those.
library;

import 'package:game_research/core/markers.dart';

/// Minimum spacing of scene frames, seconds.
const kSceneGapS = 10.0;

/// The black start-up of a recording: no scene frame before this second
/// (a marker frame may be earlier).
const kLeadInS = 2.0;

/// Stage 3's frame budget per hour of recording.
const kSynthesisFramesPerHour = 60;

/// Why a frame was taken.
enum FrameKind {
  /// A scene cut (or the start).
  scene,

  /// A marker.
  marker,
}

/// One frame to extract at [t] seconds into [file].
class SampleFrame {
  /// Creates a frame.
  const new({
    required this.t,
    required this.kind,
    required this.file,
    this.tag,
  });

  /// Reads one entry of `frames.json`.
  factory fromJson(Map<String, Object?> json) => SampleFrame(
    t: (json['t']! as num).toDouble(),
    kind: FrameKind.values.byName(json['kind']! as String),
    file: json['file']! as String,
    tag: MarkerTag.tryParse(json['tag'] as String?),
  );

  /// Seconds into the recording.
  final double t;

  /// Scene or marker.
  final FrameKind kind;

  /// File name under `analysis/frames/`.
  final String file;

  /// The marker's tag, for marker frames.
  final MarkerTag? tag;

  /// One entry of `frames.json`.
  Map<String, Object?> toJson() => {
    't': t,
    'kind': kind.name,
    'file': file,
    if (tag != null) 'tag': tag!.name,
  };
}

/// The frames stage 1 extracts, in time order, named `f_0001.png` onwards.
///
/// A marker frame past the end is clamped 0.1 s before it, so ffmpeg still
/// finds a frame there.
List<SampleFrame> sampleFrames({
  required List<double> scenes,
  required List<Marker> markers,
  required double durationS,
  double minGapS = kSceneGapS,
}) {
  final picks = <(double, FrameKind, MarkerTag?)>[];
  final lastFrame = durationS > 0.1 ? durationS - 0.1 : 0.0;
  // The first scene frame sits just after the lead-in (or at the very end of
  // a recording shorter than that).
  final first = kLeadInS <= lastFrame ? kLeadInS : lastFrame;
  double? last;
  for (final t in {
    first,
    ...scenes.where((t) => t >= kLeadInS),
  }.toList()..sort()) {
    if (t > durationS) continue;
    if (last != null && t - last < minGapS) continue;
    picks.add((t, FrameKind.scene, null));
    last = t;
  }
  for (final m in markers) {
    final t = m.offsetS > lastFrame ? lastFrame : m.offsetS;
    picks.add((t, FrameKind.marker, m.tag));
  }
  picks.sort((a, b) => a.$1.compareTo(b.$1));
  return [
    for (var i = 0; i < picks.length; i++)
      SampleFrame(
        t: picks[i].$1,
        kind: picks[i].$2,
        tag: picks[i].$3,
        file: 'f_${(i + 1).toString().padLeft(4, '0')}.png',
      ),
  ];
}

/// Stage 3's frame cap for a recording [durationS] long.
int synthesisFrameCap(double durationS) {
  final cap = (kSynthesisFramesPerHour * durationS / 3600).ceil();
  return cap < 1 ? 1 : cap;
}

/// At most [cap] of [frames]: marker frames first (earliest first), then
/// scene frames spread evenly over the session; returned in time order.
List<SampleFrame> pickSynthesisFrames(List<SampleFrame> frames, int cap) {
  final markers = frames.where((f) => f.kind == FrameKind.marker).toList();
  final scenes = frames.where((f) => f.kind == FrameKind.scene).toList();
  final picked = markers.take(cap).toList();
  final room = cap - picked.length;
  if (room >= scenes.length) {
    picked.addAll(scenes);
  } else if (room > 0) {
    // room < scenes.length, so the step is above 1 and indices never repeat.
    final step = scenes.length / room;
    for (var i = 0; i < room; i++) {
      picked.add(scenes[(i * step).floor()]);
    }
  }
  return picked..sort((a, b) => a.t.compareTo(b.t));
}
