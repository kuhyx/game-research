/// The ffmpeg command lines of a recording.
///
/// The same design as kuhy's earlier game-session recorder: x11grab of one
/// output, game
/// audio from the default sink's monitor (never a microphone), hardware
/// encode. Timestamps: frames carry the wall clock as ffmpeg reads them
/// (`-use_wallclock_as_timestamps`, pulse stamps audio the same way),
/// `-copyts` keeps them absolute and `-output_ts_offset -T0` moves them so
/// the file's timeline starts at t0, a unix time the wrapper chose. A
/// marker's offset is then press time minus t0, with no guess about ffmpeg's
/// start-up latency. x11grab hands a frame over 1-2 frame periods after the
/// screen had it, so the video input is shifted back 1.5 frames.
///
/// Quality over size (kuhy): HEVC NVENC at constant quality 14, FLAC audio,
/// Matroska. Nothing is ever re-encoded smaller afterwards.
library;

import 'package:game_research/core/xrandr.dart';

/// NVENC HEVC, the default.
const kNvencHevc = 'hevc_nvenc';

/// NVENC H.264, when HEVC is unavailable.
const kNvencH264 = 'h264_nvenc';

/// Software fallback.
const kX264 = 'libx264';

const _grabLatencyFrames = 1.5;

/// One recording.
class RecordSpec {
  /// Creates a spec.
  const new({
    required this.output,
    required this.display,
    required this.fps,
    required this.t0Unix,
    required this.out,
    this.audio = 'default',
    this.codec = kNvencHevc,
  });

  /// The monitor to grab.
  final Output output;

  /// X display (`:0`).
  final String display;

  /// Frames per second.
  final int fps;

  /// Unix time that becomes 0 on the file's timeline.
  final double t0Unix;

  /// Output `.mkv`.
  final String out;

  /// `default` (monitor of the default sink), a `*.monitor` source, or
  /// `lavfi` (wall-clock stamped silence, tests only).
  final String audio;

  /// Encoder name.
  final String codec;
}

/// The best usable encoder, or null when none works.
String? pickEncoder(Set<String> usable) {
  for (final name in const [kNvencHevc, kNvencH264, kX264]) {
    if (usable.contains(name)) return name;
  }
  return null;
}

/// Encodes one synthetic frame with [codec]: listed is not the same as
/// working (a busy or absent GPU fails here, not mid-session).
List<String> encoderProbeArgs(String codec) => [
  'ffmpeg',
  '-v',
  'error',
  '-f',
  'lavfi',
  '-i',
  'color=size=256x256:rate=1',
  '-frames:v',
  '1',
  '-c:v',
  codec,
  '-f',
  'null',
  '-',
];

// One keyframe a second: marker clips are cut by stream copy, which starts
// at the keyframe before the cut, so a clip is at most 1 s longer than asked.
List<String> _videoCodec(String codec, int fps) => switch (codec) {
  kX264 => ['-c:v', kX264, '-crf', '12', '-preset', 'veryfast', '-g', '$fps'],
  _ => [
    '-c:v',
    codec,
    '-preset',
    'p5',
    '-tune',
    'hq',
    '-rc',
    'vbr',
    '-cq',
    '14',
    '-b:v',
    '0',
    '-g',
    '$fps',
  ],
};

List<String> _audio(String audio) {
  if (audio == 'lavfi') {
    return ['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo'];
  }
  if (audio != 'default' && !audio.endsWith('.monitor')) {
    throw ArgumentError.value(audio, 'audio', 'only a .monitor source');
  }
  final source = audio == 'default' ? '@DEFAULT_MONITOR@' : audio;
  return ['-thread_queue_size', '1024', '-f', 'pulse', '-i', source];
}

/// The recording argv. SIGINT makes ffmpeg finalise the file.
List<String> ffmpegRecordArgs(RecordSpec s) => [
  'ffmpeg',
  '-hide_banner',
  '-loglevel',
  'warning',
  '-nostdin',
  '-y',
  '-thread_queue_size',
  '1024',
  '-use_wallclock_as_timestamps',
  '1',
  '-itsoffset',
  (-_grabLatencyFrames / s.fps).toStringAsFixed(6),
  '-f',
  'x11grab',
  '-video_size',
  s.output.videoSize,
  '-framerate',
  '${s.fps}',
  '-draw_mouse',
  '0',
  '-i',
  s.output.grabInput(s.display),
  ..._audio(s.audio),
  '-copyts',
  '-output_ts_offset',
  (-s.t0Unix).toStringAsFixed(6),
  if (s.audio == 'lavfi') ...['-af', "asetpts='RTCTIME/(1000000*TB)'"],
  ..._videoCodec(s.codec, s.fps),
  '-c:a',
  'flac',
  '-f',
  'matroska',
  s.out,
];

/// Remuxes [video] with the chapters in [ffmeta] into [tmp], streams copied
/// and timestamps kept.
List<String> embedChaptersArgs(String video, String ffmeta, String tmp) => [
  'ffmpeg',
  '-v',
  'error',
  '-y',
  '-copyts',
  '-i',
  video,
  '-f',
  'ffmetadata',
  '-i',
  ffmeta,
  '-map',
  '0',
  '-map_metadata',
  '0',
  '-map_chapters',
  '1',
  '-c',
  'copy',
  '-f',
  'matroska',
  tmp,
];
