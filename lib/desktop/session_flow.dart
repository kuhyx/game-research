/// From "open PlayStudy" to "recording": the autostart countdown, the Steam
/// launch, the wait for the game window, then the session controller.
///
/// Phases: idle -> armed (ring drains `Config.autostartS`) -> launching
/// (Steam command) -> waiting (game window not up yet; Steam may still be
/// starting or finishing a download) -> recording. Stop or Esc cancels any
/// pending phase. Every failure lands in [SessionFlow.error] (the GUI's
/// error glyph) and in the event log.
library;

import 'dart:async';

import 'package:game_research/core/steam.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/session_controller.dart';
import 'package:game_research/desktop/session_parts.dart';
import 'package:game_research/desktop/steam_library.dart';

/// Where the flow is.
enum Phase {
  /// Nothing pending, nothing recording.
  idle,

  /// The autostart ring is draining.
  armed,

  /// The Steam command runs.
  launching,

  /// Waiting for the game window.
  waiting,

  /// A session records.
  recording,
}

/// The flow over one controller.
class SessionFlow {
  /// Creates the flow; [every] is the window poll interval.
  new(this.controller, this.library, {this.every = const Duration(seconds: 1)});

  /// The recording state machine.
  final SessionController controller;

  /// Installed and updating games.
  final SteamLibrary library;

  /// Window poll interval.
  final Duration every;

  Phase _phase = Phase.idle;
  int? _appid;
  double? _deadline;
  Timer? _timer;
  int _gen = 0;

  /// Why the last flow step failed ('' when it did not).
  String error = '';

  SessionParts get _parts => controller.parts;

  /// The current phase.
  Phase get phase => controller.recording ? Phase.recording : _phase;

  bool get _pending =>
      const {Phase.armed, Phase.launching, Phase.waiting}.contains(phase);

  /// The game autostart and a bare `start` use: the last one, else the
  /// configured default (Librarian).
  int lastAppid() {
    final v = _parts.targets.settings.read()['last_appid'];
    return v is int ? v : _parts.config.defaultAppid;
  }

  /// `/api/state`: the controller's state plus the phase and what is pending.
  Map<String, Object?> state() {
    final err = error.isNotEmpty ? error : controller.lastError;
    return {
      ...controller.state(),
      'error': err,
      'phase': phase.name,
      if (_pending)
        'pending': {
          'appid': _appid,
          if (phase == Phase.armed) 'deadline_unix': _deadline,
          if (phase == Phase.armed) 'total_s': _parts.config.autostartS,
        },
    };
  }

  /// Arms the autostart of [appid] (default [lastAppid]); false when a
  /// session is pending or recording.
  bool arm({int? appid}) {
    if (_pending || controller.recording) return false;
    final id = appid ?? lastAppid();
    final secs = _parts.config.autostartS;
    _phase = Phase.armed;
    _appid = id;
    _deadline = _parts.sys.nowUnix() + secs;
    error = '';
    final gen = ++_gen;
    _parts.log.event('autostart_arm', {'appid': id, 'seconds': secs});
    _timer = Timer(Duration(milliseconds: (secs * 1000).round()), () {
      if (gen != _gen) return;
      _parts.log.event('autostart_fire', {'appid': id});
      unawaited(start(id).catchError((Object _) {}));
    });
    return true;
  }

  /// Cancels a pending phase; false when nothing was pending.
  bool cancel(String by) {
    if (!_pending) return false;
    _timer?.cancel();
    _gen++;
    _parts.log.event('cancel', {'phase': phase.name, 'by': by});
    _phase = Phase.idle;
    return true;
  }

  Never _fail(String step, String message) {
    error = message;
    _phase = Phase.idle;
    _parts.log.event('error', {'step': step, 'message': message});
    throw StartError(message);
  }

  /// Launches [appid] through Steam and waits for its window in the
  /// background. Throws [StartError] (kept in [error]) when it cannot.
  Future<void> start(int appid) async {
    if (controller.recording ||
        const {Phase.launching, Phase.waiting}.contains(_phase)) {
      throw const StartError('a session is pending or recording');
    }
    _timer?.cancel();
    final gen = ++_gen;
    error = '';
    controller.lastError = '';
    _appid = appid;
    final game = library.find(appid);
    if (game == null) _fail('pick', 'game $appid is not in the Steam library');
    _parts.targets.settings.merge({'last_appid': appid});
    _phase = Phase.launching;
    if (_parts.launcher.scan.running(appid) ?? false) {
      // A second URI for a running game only gets Steam's error toast.
      _parts.log.event('already_running', {'appid': appid});
    } else {
      try {
        await _parts.launcher.launch(appid);
      } on StartError catch (e) {
        if (gen == _gen) _fail('launch', e.message);
        rethrow;
      }
    }
    if (gen != _gen) return; // cancelled while Steam ran
    _phase = Phase.waiting;
    _parts.log.event('waiting', {'appid': appid});
    unawaited(_await(game, gen));
  }

  /// Whether Steam's client is up but no process of [appid] runs: Steam
  /// finished an update the launch URI started and never launched it.
  bool _stalled(int appid) {
    final scan = _parts.launcher.scan;
    return scan.steamClient(_parts.config.steamPidFile) != null &&
        scan.running(appid) == false;
  }

  Future<void> _await(SteamGame game, int gen) async {
    final until = _parts.sys.nowUnix() + _parts.config.windowTimeoutS;
    var handed = _parts.sys.nowUnix();
    while (gen == _gen) {
      final hit = await _parts.window.find(game.appid);
      if (gen != _gen) return;
      if (hit != null) {
        _parts.log.event('window', {'pid': hit.pid, 'window': hit.window});
        _phase = Phase.idle;
        try {
          await controller.start(game);
        } on StartError catch (e) {
          error = e.message;
        }
        return;
      }
      final now = _parts.sys.nowUnix();
      if (now > until) {
        error = 'the game window never appeared';
        _phase = Phase.idle;
        _parts.log.event('error', {'step': 'window', 'message': error});
        return;
      }
      if (now - handed >= _parts.config.relaunchS && _stalled(game.appid)) {
        handed = now;
        _parts.log.event('relaunch', {'appid': game.appid});
        try {
          await _parts.launcher.launch(game.appid);
        } on StartError {
          // logged by the launcher; the next round tries again
        }
      }
      await Future<void>.delayed(every);
    }
  }
}
