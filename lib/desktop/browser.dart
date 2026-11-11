/// The Chrome `--app` window the GUI runs in.
library;

import 'dart:io';

import 'package:game_research/core/xrandr.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// Browser profile. Fixed: Chrome keys zoom and page state by profile and
/// origin, so a moving profile (or port) is a fresh window every launch.
String profileDir(String home) =>
    p.join(home, '.local', 'share', 'game-research', 'profile');

/// The window's WM_CLASS; the `.desktop` StartupWMClass matches it.
const kWindowClass = 'game-research';

/// The first Chrome-family binary, or ''. The real chromium binary comes
/// before the /usr/bin launcher: that launcher reads
/// ~/.config/chromium-flags.conf, whose --load-extension opens a stray
/// claude.ai window beside the app.
String findBrowser({String? override, bool Function(String)? exists}) {
  final candidates = [
    override ?? Platform.environment['GAME_RESEARCH_BROWSER'] ?? '',
    '/usr/lib/chromium/chromium',
    '/usr/bin/chromium',
    '/usr/bin/google-chrome-stable',
    '/opt/google/chrome/chrome',
  ];
  return candidates.firstWhere(
    (c) => c.isNotEmpty && (exists ?? (x) => File(x).existsSync())(c),
    orElse: () => '',
  );
}

/// `--force-device-scale-factor=` for [scale]: `2`, not `2.0`.
String scaleFlag(double scale) {
  final text = scale == scale.roundToDouble()
      ? scale.toInt().toString()
      : scale.toString();
  return '--force-device-scale-factor=$text';
}

/// The window's scale: `$GAME_RESEARCH_SCALE` if sane, else read from the
/// output the window is meant for (HDMI-0 2560x1440 gives 1.25), else the
/// primary, else 1.
Future<double> detectScale(
  Sys sys, {
  String? override,
  String windowOutput = 'HDMI-0',
}) async {
  final fixed = double.tryParse(override ?? '');
  if (fixed != null && fixed > 0 && fixed <= 4) return fixed;
  final r = await sys.run('xrandr', ['--query']);
  if (r.exitCode != 0) return 1;
  final outputs = parseXrandr('${r.stdout}');
  final target =
      findOutput(outputs, windowOutput) ??
      outputs.where((o) => o.primary).firstOrNull;
  return scaleFor(target);
}

/// Arguments for the app window on [port] at [scale].
List<String> browserArgs(String home, {required int port, double scale = 1}) =>
    [
      '--app=http://127.0.0.1:$port',
      scaleFlag(scale),
      '--user-data-dir=${profileDir(home)}',
      '--class=$kWindowClass',
      '--no-first-run',
      '--no-default-browser-check',
      // No extension: the flags file's forced one opens its own window.
      '--disable-extensions',
      '--disable-session-crashed-bubble',
      '--hide-crash-restore-bubble',
      // Off the desktop keyring: a locked one blocks the first page load.
      '--password-store=basic',
    ];
