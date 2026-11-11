/// A [SessionController] wired to fakes, a temp data dir and a temp /proc.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/game_watcher.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/session_controller.dart';
import 'package:game_research/desktop/session_parts.dart';
import 'package:game_research/desktop/session_services.dart';
import 'package:game_research/desktop/session_store.dart';
import 'package:game_research/desktop/targets.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';

/// One xrandr screen with DP-2.
const kXrandr = 'DP-2 connected 3840x2160+0+0 (normal) 1mm x 1mm\n';

/// Everything a controller test needs.
class Harness {
  /// Builds the harness under a fresh temp dir.
  new({Map<String, String> extra = const {}}) {
    root = tempDir();
    proc = Directory(p.join(root.path, 'proc'))..createSync();
    config = testConfig(root, extra: extra);
    fake.onRun = _run;
    fake.onStart = _start;
    final sys = fake.sys;
    watcher = GameWatcher(
      procRoot: proc.path,
      every: const Duration(milliseconds: 10),
    );
    parts = SessionParts(
      config: config,
      sys: sys,
      recorder: Recorder(config, sys),
      hotkeys: HotkeyService(config, sys),
      overlay: Overlay(config, sys),
      asker: NoteAsker(config, sys),
      launcher: GameLauncher(config, sys),
      watcher: watcher,
      store: SessionStore(config),
      analysis: AnalysisLauncher(config, sys),
      targets: Targets(config),
    );
    controller = SessionController(parts);
    // Runs before the temp dir goes: lets ffmpeg.log finish opening.
    addTearDown(() async {
      watcher.cancel();
      await settle();
    });
  }

  /// Temp root.
  late final Directory root;

  /// Fake /proc.
  late final Directory proc;

  /// Settings.
  late final Config config;

  /// The seam.
  final fake = FakeSys();

  /// Game watcher over [proc].
  late final GameWatcher watcher;

  /// The parts.
  late final SessionParts parts;

  /// The unit under test.
  late final SessionController controller;

  /// What `dmenu` answers.
  String dmenuText = 'asked note\n';

  /// Keep dmenu open until killed.
  bool dmenuHangs = false;

  /// Exe names whose `run` fails.
  final failRuns = <String>{};

  /// Exe names whose `start` throws a [ProcessException].
  final failStarts = <String>{};

  /// The running ffmpeg recording process.
  late FakeProcess ffmpeg;

  ProcessResult? _run(Call c) {
    if (failRuns.contains(c.exe)) return bad('${c.exe} failed');
    switch (c.exe) {
      case 'xrandr':
        return ok(kXrandr);
      case 'ffprobe':
        return ok(
          jsonEncode({
            'format': {'duration': '42.5'},
          }),
        );
      case 'ffmpeg' when c.args.last.endsWith('.chapters.mkv'):
        File(c.args.last).writeAsStringSync('chaptered');
    }
    return null;
  }

  FakeProcess? _start(Call c) {
    if (failStarts.contains(c.exe)) {
      throw ProcessException(c.exe, c.args, 'not installed');
    }
    return switch (c.exe) {
      'ffmpeg' => ffmpeg = FakeProcess(),
      'python3' => FakeProcess(),
      'dmenu' =>
        dmenuHangs
            ? FakeProcess()
            : FakeProcess(exit: 0, stdoutText: dmenuText),
      _ => null,
    };
  }

  /// Marks a fake process of [appid] as running.
  void gameRuns(int appid) {
    final dir = Directory(p.join(proc.path, '77'))..createSync();
    File(p.join(dir.path, 'cmdline'))
        .writeAsStringSync('reaper\x00AppId=$appid');
  }

  /// The game exits.
  void gameExits() =>
      Directory(p.join(proc.path, '77')).deleteSync(recursive: true);

  /// The single session folder.
  Directory get sessionDir =>
      Directory(config.dataDir).listSync().whereType<Directory>().single;

  /// `session.json` of [sessionDir].
  Map<String, Object?> get meta => jsonDecode(
    File(p.join(sessionDir.path, 'session.json')).readAsStringSync(),
  ) as Map<String, Object?>;

  /// Marker lines written so far.
  List<Map<String, Object?>> get markerLines {
    final f = File(p.join(sessionDir.path, 'markers.jsonl'));
    if (!f.existsSync()) return const [];
    return [
      for (final l in const LineSplitter().convert(f.readAsStringSync()))
        jsonDecode(l) as Map<String, Object?>,
    ];
  }

  /// Waits until no session records.
  Future<void> untilStopped() async {
    for (var i = 0; i < 100 && controller.recording; i++) {
      await settle();
    }
  }
}
