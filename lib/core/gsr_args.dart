/// The gpu-screen-recorder command line: capture and encode on the GPU.
///
/// x11grab copies every 4K frame through the CPU before NVENC sees it (about
/// 1 GB/s at 30 fps); gpu-screen-recorder grabs with NvFBC and encodes on
/// the same GPU, so the game keeps the CPU (kuhy, 2026-11-11: "the game runs
/// slow"). It needs a real GPU-backed X server: under Xvfb it fails to load
/// OpenGL and the recorder falls back to x11grab.
///
/// Timestamps: gsr's file starts at its first frame, not at the wrapper's
/// t0. `-write-first-frame-ts` writes that frame's wall clock beside the
/// video; the chapter remux shifts the streams by `first - t0`, so file time
/// 0 is t0 exactly as on the x11grab path and marker offsets need no change.
library;

import 'package:game_research/core/recorder_args.dart';
import 'package:game_research/core/xrandr.dart';

/// The binary, also the `codec` of a gsr [RecordSpec].
const kGsr = 'gpu-screen-recorder';

/// Lists monitors only. `--list-capture-options` would also open the webcam.
const List<String> gsrProbeArgs = [kGsr, '--list-monitors'];

/// Whether the [listing] of [gsrProbeArgs] can capture [output]: its RandR
/// name is listed, or (an explicit `WxH+X+Y`) any monitor is.
bool gsrLists(String listing, Output output) {
  final names = [
    for (final line in listing.split('\n'))
      if (line.contains('|')) line.split('|').first.trim(),
  ];
  return output.name == 'geometry'
      ? names.isNotEmpty
      : names.contains(output.name);
}

/// How much later than its capture gsr stamps the first frame's wall
/// clock (encode latency). Measured 2026-11-11 on kuhy's RTX 3090 at 4K30
/// with `tool/marker_lag.py`: 0.112 and 0.134 s from a flash's draw time to
/// its frame. Re-measure there after a gsr or driver upgrade.
const kGsrStampLagS = 0.12;

/// The first-frame timestamp file gsr writes beside [video].
String gsrTsPath(String video) => '$video.ts';

/// The first frame's wall clock (unix seconds) from a [gsrTsPath] file:
/// `monotonic_microsec realtime_microsec`, maybe under a header line.
double? parseFirstFrameTs(String text) {
  for (final line in text.split('\n').reversed) {
    final cols = line.trim().split(RegExp(r'\s+'));
    if (cols.length < 2) continue;
    final realtime = int.tryParse(cols[1]);
    if (realtime != null) return realtime / 1e6;
  }
  return null;
}

List<String> _audio(String audio) {
  if (audio == 'lavfi') return const []; // tests: no audio device at all
  if (audio != 'default' && !audio.endsWith('.monitor')) {
    throw ArgumentError.value(audio, 'audio', 'only a .monitor source');
  }
  // default_output is the default sink's monitor (game audio), never a mic.
  return ['-a', if (audio == 'default') 'default_output' else audio];
}

/// The recording argv. SIGINT makes gsr finalise the file.
List<String> gsrRecordArgs(RecordSpec s) => [
  kGsr,
  if (s.output.name == 'geometry') ...[
    '-w',
    'region',
    '-region',
    s.output.geometry,
  ] else ...[
    '-w',
    s.output.name,
  ],
  '-c',
  'mkv',
  '-f',
  '${s.fps}',
  '-k',
  'hevc',
  '-encoder',
  'gpu',
  // Constant quality; very_high (kuhy, 2026-11-12: ultra was too heavy).
  '-bm',
  'qp',
  '-q',
  'very_high',
  // Marker clips are cut by stream copy at the keyframe before the cut.
  '-keyint',
  '1',
  '-cursor',
  'no',
  ..._audio(s.audio),
  // gsr disables flac and warns; opus is the supported audio codec for mkv.
  '-ac',
  'opus',
  '-write-first-frame-ts',
  'yes',
  '-o',
  s.out,
];
