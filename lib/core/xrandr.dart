/// Monitors from `xrandr --query`: what to record and what scale to open at.
///
/// kuhy's layout (2026-11): DP-2 3840x2160 at +0+0 runs the game, HDMI-0
/// 2560x1440 at +3840+0 (primary) holds this app. The recorder grabs one
/// named output and fails closed when it is missing rather than grabbing
/// another one.
library;

import 'dart:math' as math;

/// One connected output with a mode.
class Output {
  /// Creates an output.
  const new({
    required this.name,
    required this.width,
    required this.height,
    this.x = 0,
    this.y = 0,
    this.primary = false,
  });

  /// RandR name (`DP-2`), or `geometry` for one given as WxH+X+Y.
  final String name;

  /// Width, pixels.
  final int width;

  /// Height, pixels.
  final int height;

  /// Left edge on the X screen.
  final int x;

  /// Top edge on the X screen.
  final int y;

  /// Whether xrandr marks it primary.
  final bool primary;

  /// ffmpeg's `-video_size`.
  String get videoSize => '${width}x$height';

  /// ffmpeg x11grab's input for [display]: `:0+3840,0`.
  String grabInput(String display) => '$display+$x,$y';

  /// `WxH+X+Y`, the flash overlay's geometry.
  String get geometry => '${width}x$height+$x+$y';
}

final _connected = RegExp(
  r'^(\S+) connected (primary )?(\d+)x(\d+)\+(\d+)\+(\d+)',
  multiLine: true,
);

/// Connected outputs with a mode, in xrandr's order.
List<Output> parseXrandr(String query) => [
  for (final m in _connected.allMatches(query))
    Output(
      name: m[1]!,
      primary: m[2] != null,
      width: int.parse(m[3]!),
      height: int.parse(m[4]!),
      x: int.parse(m[5]!),
      y: int.parse(m[6]!),
    ),
];

/// The output named [name], or null.
Output? findOutput(List<Output> outputs, String name) {
  for (final o in outputs) {
    if (o.name == name) return o;
  }
  return null;
}

/// An output from an explicit `WxH+X+Y`, or null.
Output? parseGeometry(String text) {
  final m = RegExp(r'^(\d+)x(\d+)\+(\d+)\+(\d+)$').firstMatch(text.trim());
  if (m == null) return null;
  return Output(
    name: 'geometry',
    width: int.parse(m[1]!),
    height: int.parse(m[2]!),
    x: int.parse(m[3]!),
    y: int.parse(m[4]!),
  );
}

/// Device scale for a window on [output]: short side over 1080, to the
/// nearest quarter, between 1 and 3 (2160p gives 2, 1440p 1.25).
double scaleFor(Output? output) {
  if (output == null) return 1;
  final short = math.min(output.width, output.height);
  return ((short / 1080 * 4).round() / 4).clamp(1.0, 3.0);
}
