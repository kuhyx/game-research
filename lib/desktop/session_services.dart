/// The side effects a session switches on and off: hotkeys, the flash and
/// tick and the dmenu note line.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/hotkeys.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/xrandr.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// sxhkd with a generated config, as its own `systemd-run --user` unit: the
/// unit name is fixed per port, so a wrapper that crashed mid-session gets
/// its stale grabber stopped on the next start ([stop] is idempotent).
class HotkeyService {
  /// Creates the service.
  const new(this.config, this.sys);

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  /// The transient unit's name.
  String get unit => 'game-research-keys-${config.port}';

  /// Starts grabbing; throws [StartError] when i3 already binds a chord.
  Future<void> start(String sessionDir) async {
    final i3 = File(config.i3Config);
    final taken = i3.existsSync()
        ? i3Collisions(i3.readAsStringSync())
        : <String>[];
    if (taken.isNotEmpty) {
      throw StartError('i3 already binds ${taken.join(', ')}');
    }
    final cfg = File(p.join(sessionDir, 'sxhkdrc'))
      ..writeAsStringSync(sxhkdConfig(port: config.port));
    await stop();
    final r = await sys.run('systemd-run', [
      '--user',
      '--collect',
      '--quiet',
      '--unit',
      unit,
      '--setenv=DISPLAY=${config.display}',
      'sxhkd',
      '-c',
      cfg.path,
    ]);
    if (r.exitCode != 0) throw StartError('sxhkd did not start: ${r.stderr}');
  }

  /// Releases the keys.
  Future<void> stop() async {
    await sys.run('systemctl', ['--user', 'stop', '$unit.service']);
  }
}

/// The border flash (a Tk helper with four edge strips over the game's
/// output, fed colours on stdin) and the tick sound.
class Overlay {
  /// Creates the overlay.
  new(this.config, this.sys);

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;
  Process? _flash;
  StreamSubscription<String>? _shown;

  /// Starts the flash helper over [output]. It exits on stdin EOF, so it
  /// cannot outlive a crashed wrapper. Each `shown <tag> <unix>` line it
  /// prints (the flash is on screen) is appended to [flashLog] as
  /// `{"tag", "shown_unix"}`; anything else is ignored.
  Future<void> start(Output output, {File? flashLog}) async {
    _flash = await sys.start(
      'python3',
      [
        p.join(config.repo, 'helpers', 'flash_overlay.py'),
        '--geometry',
        output.geometry,
        '--thickness',
        '${config.flashPx}',
        '--ms',
        '300',
      ],
      environment: {'DISPLAY': config.display},
    );
    _shown = _flash!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _logShown(line, flashLog));
    unawaited(_flash!.stderr.drain<void>());
  }

  void _logShown(String line, File? log) {
    final parts = line.trim().split(' ');
    final unix = parts.length == 3 && parts[0] == 'shown'
        ? double.tryParse(parts[2])
        : null;
    if (log == null || unix == null) return;
    log.writeAsStringSync(
      '${jsonEncode({'tag': parts[1], 'shown_unix': unix})}\n',
      mode: FileMode.append,
    );
  }

  /// Flashes [tag]'s colour and plays the tick.
  Future<void> mark(MarkerTag tag) async {
    _flash?.stdin.writeln('${tag.flashHex} ${tag.name}');
    if (config.tickCmd.isEmpty) return;
    try {
      await sys.start(config.tickCmd.first, [
        ...config.tickCmd.skip(1),
        tag.name,
      ], mode: ProcessStartMode.detached);
    } on ProcessException {
      // No player installed: the flash alone confirms the marker.
    }
  }

  /// Stops the flash helper.
  Future<void> stop() async {
    final flash = _flash;
    _flash = null;
    if (flash == null) return;
    unawaited(_shown?.cancel());
    _shown = null;
    await flash.stdin.close();
    flash.kill();
  }
}

/// The text-free dmenu line for a hotkey note: no prompt, no items.
class NoteAsker {
  /// Creates the asker.
  new(this.config, this.sys);

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;
  final _open = <Process>{};

  /// What kuhy typed ('' on Escape or when [cancelAll] closed it).
  Future<String> ask() async {
    final Process proc;
    try {
      proc = await sys.start(
        'dmenu',
        [
          '-p',
          '',
          '-fn',
          'monospace-22',
          '-nb',
          '#211D1B',
          '-nf',
          '#ECEAE9',
          '-sb',
          '#2f6fe2',
          '-sf',
          '#ECEAE9',
        ],
        environment: {'DISPLAY': config.display},
      );
    } on ProcessException {
      return '';
    }
    _open.add(proc);
    unawaited(proc.stdin.close());
    unawaited(proc.stderr.drain<void>());
    final out = await proc.stdout.transform(utf8.decoder).join();
    await proc.exitCode;
    _open.remove(proc);
    return out.split('\n').first.trim();
  }

  /// Closes every open line (session stop).
  void cancelAll() {
    for (final proc in _open) {
      proc.kill();
    }
  }
}
