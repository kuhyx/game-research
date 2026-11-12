/// The services a session switches on and off, bundled for the controller.
library;

import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/fps_session.dart';
import 'package:game_research/desktop/game_watcher.dart';
import 'package:game_research/desktop/proc_scan.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/session_services.dart';
import 'package:game_research/desktop/session_store.dart';
import 'package:game_research/desktop/steam_launch.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:game_research/desktop/targets.dart';

/// Everything the session controller drives.
class SessionParts {
  /// Bundles the parts.
  new({
    required this.config,
    required this.sys,
    required this.recorder,
    required this.hotkeys,
    required this.overlay,
    required this.asker,
    required this.launcher,
    required this.watcher,
    required this.store,
    required this.analysis,
    required this.targets,
    required this.log,
    required this.window,
    FpsSession? fps,
  }) : fps = fps ?? FpsSession(config, sys, log);

  /// The real parts for [config] and [sys].
  factory real(Config config, Sys sys) {
    final scan = ProcScan(config.procRoot);
    final log = EventLog(config.logFile);
    return SessionParts(
      config: config,
      sys: sys,
      recorder: Recorder(config, sys),
      hotkeys: HotkeyService(config, sys),
      overlay: Overlay(config, sys),
      asker: NoteAsker(config, sys),
      launcher: GameLauncher(config, sys, scan, log),
      watcher: GameWatcher(procRoot: config.procRoot),
      store: SessionStore(config),
      analysis: AnalysisLauncher(config, sys),
      targets: Targets(config),
      log: log,
      window: GameWindow(config, sys, scan),
      fps: FpsSession(config, sys, log),
    );
  }

  /// Settings.
  final Config config;

  /// OS seam.
  final Sys sys;

  /// ffmpeg.
  final Recorder recorder;

  /// sxhkd.
  final HotkeyService hotkeys;

  /// Flash + tick.
  final Overlay overlay;

  /// dmenu note line.
  final NoteAsker asker;

  /// Steam.
  final GameLauncher launcher;

  /// Game process watch.
  final GameWatcher watcher;

  /// Session folders.
  final SessionStore store;

  /// Analysis job.
  final AnalysisLauncher analysis;

  /// Target projects.
  final Targets targets;

  /// The JSON-lines event log.
  final EventLog log;

  /// Finds the game's window.
  final GameWindow window;

  /// MangoHud launch option and frame-rate logs.
  final FpsSession fps;
}
