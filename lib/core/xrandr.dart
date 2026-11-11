/// Monitors from xrandr: what to record and what scale to open at.
///
/// The recorder grabs the monitor the game window is on (`--listmonitors`
/// intersected with the window rect), else the primary one. It never trusts
/// a remembered output name: on 2026-11-11 the default `DP-2` did not exist
/// on kuhy's :0 (DP-0 3840x2160 primary at +0+0, HDMI-0 2560x1440 at
/// +3840+0) and every session died at 00:00.
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

/// A window or monitor rectangle in X screen coordinates.
typedef Rect = ({int x, int y, int width, int height});

/// [r] as `WxH+X+Y`, for the event log.
String rectText(Rect r) => '${r.width}x${r.height}+${r.x}+${r.y}';

/// The output to record and why: `pinned`, `window`, `primary`, `first`
/// (or `geometry` for an explicit `WxH+X+Y`).
typedef OutputPick = ({Output output, String why});

final _monitor = RegExp(
  r'^\s*\d+:\s+\+?(\*?)(\S+)\s+(\d+)/\d+x(\d+)/\d+\+(-?\d+)\+(-?\d+)',
  multiLine: true,
);

/// Monitors from `xrandr --listmonitors` (`*` marks the primary one).
List<Output> parseMonitors(String text) => [
  for (final m in _monitor.allMatches(text))
    Output(
      name: m[2]!,
      primary: m[1]!.isNotEmpty,
      width: int.parse(m[3]!),
      height: int.parse(m[4]!),
      x: int.parse(m[5]!),
      y: int.parse(m[6]!),
    ),
];

int _overlap(Output o, Rect r) {
  final w =
      math.min<int>(o.x + o.width, r.x + r.width) - math.max<int>(o.x, r.x);
  final h =
      math.min<int>(o.y + o.height, r.y + r.height) - math.max<int>(o.y, r.y);
  return w > 0 && h > 0 ? w * h : 0;
}

/// The monitor to record: [pin] when it exists, else the one sharing the
/// most area with [window], else the primary, else the first; null when
/// there is no monitor at all.
OutputPick? pickOutput(List<Output> monitors, {Rect? window, String pin = ''}) {
  if (monitors.isEmpty) return null;
  final pinned = findOutput(monitors, pin);
  if (pinned != null) return (output: pinned, why: 'pinned');
  if (window != null) {
    final best = monitors.reduce(
      (a, b) => _overlap(b, window) > _overlap(a, window) ? b : a,
    );
    if (_overlap(best, window) > 0) return (output: best, why: 'window');
  }
  for (final o in monitors) {
    if (o.primary) return (output: o, why: 'primary');
  }
  return (output: monitors.first, why: 'first');
}
