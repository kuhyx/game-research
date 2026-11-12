/// One recording session at a time: start, markers, stop.
///
/// Start (called by `SessionFlow` once the game window is up): resolve the
/// output and encoder (fail closed), pick t0, start ffmpeg, the hotkeys and
/// the flash helper, then watch the game.
/// Stop (button, Mod+Shift+F4, game exit or ffmpeg dying): release the
/// keys, close pending notes, finalise ffmpeg, write chapters and
/// `session.json`, start the analysis job.
library;

import 'dart:async';
import 'dart:io';

import 'package:game_research/core/markers.dart';
import 'package:game_research/core/recorder_args.dart';
import 'package:game_research/core/slug.dart';
import 'package:game_research/core/steam.dart';
import 'package:game_research/core/xrandr.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/session_parts.dart';
import 'package:path/path.dart' as p;

class _Active {
  new(this.dir, this.game, this.t0, this.recording, this.meta);
  final Directory dir;
  final SteamGame game;
  final double t0;
  final Recording recording;
  final Map<String, Object?> meta;
  final markers = <Marker>[];
  final pending = <int, Marker>{};
  final asks = <Future<void>>[];
  int nextHold = 1;
  bool stopping = false;
}

/// The session state machine.
class SessionController {
  /// Creates the controller over [parts].
  new(this.parts);

  /// The services a session switches on and off.
  final SessionParts parts;
  _Active? _active;

  /// Why the last start or stop failed ('' when it did not).
  String lastError = '';

  /// Whether a session records now.
  bool get recording => _active != null;

  /// `/api/state`.
  Map<String, Object?> state() {
    final a = _active;
    return {
      'recording': a != null,
      'error': lastError,
      'target': parts.targets.current(),
      if (a != null)
        'session': {
          'id': p.basename(a.dir.path),
          'appid': a.game.appid,
          'started_unix': a.t0,
          'markers': {
            for (final e in countByTag([
              ...a.markers,
              ...a.pending.values,
            ]).entries)
              e.key.name: e.value,
          },
        },
    };
  }

  /// Starts a session of [game]. Throws [StartError] (also kept in
  /// [lastError]) when anything needed is missing; nothing is left running.
  /// [window] is the game window's rect: its monitor is recorded.
  Future<void> start(SteamGame game, {Rect? window}) async {
    if (_active != null) throw const StartError('a session is recording');
    lastError = '';
    try {
      await _start(game, window);
    } on StartError catch (e) {
      lastError = e.message;
      parts.log.event('error', {'step': 'record_start', 'message': e.message});
      rethrow;
    }
  }

  Future<void> _start(SteamGame game, Rect? window) async {
    final pick = await parts.recorder.resolveOutput(window: window);
    if (pick == null) throw const StartError('no monitor found');
    final output = pick.output;
    final codec = await parts.recorder.probeCapture(output);
    if (codec == null) throw const StartError('no working video encoder');
    final now = DateTime.fromMicrosecondsSinceEpoch(
      (parts.sys.nowUnix() * 1e6).round(),
    );
    final dir = Directory(
      p.join(parts.config.dataDir, sessionId(now, slugify(game.name))),
    )..createSync(recursive: true);
    final t0 = parts.sys.nowUnix();
    final Recording rec;
    try {
      await parts.hotkeys.start(dir.path);
      rec = await parts.recorder.start(
        RecordSpec(
          output: output,
          display: parts.config.display,
          fps: parts.config.fps,
          t0Unix: t0,
          out: p.join(dir.path, 'recording.mkv'),
          audio: parts.config.audio,
          codec: codec,
        ),
      );
    } on Object {
      // Nothing recorded: release the keys and leave no empty folder.
      await parts.hotkeys.stop();
      dir.deleteSync(recursive: true);
      rethrow;
    }
    final meta = <String, Object?>{
      'appid': game.appid,
      'game': game.name,
      'slug': slugify(game.name),
      't0_unix': t0,
      'started_unix': t0,
      'state': 'recording',
      'encoder': rec.codec,
      'output': output.name,
      'output_why': pick.why,
      'video': 'recording.mkv',
      'target': parts.targets.current(),
      'display': parts.config.display,
    };
    parts.store.writeMeta(dir, meta);
    final active = _Active(dir, game, t0, rec, meta);
    _active = active;
    final flashes = File(p.join(dir.path, 'flashes.jsonl'));
    await parts.overlay.start(output, flashLog: flashes);
    unawaited(
      rec.exited.then((_) {
        if (identical(_active, active) && !active.stopping) {
          unawaited(stop(endedBy: 'recorder-exit'));
        }
      }),
    );
    parts.watcher.watch(
      game.appid,
      () => unawaited(stop(endedBy: 'game-exit')),
    );
    parts.log.event('record_start', {
      'session': p.basename(dir.path),
      'appid': game.appid,
      'encoder': rec.codec,
      if (rec.codec != codec) 'capture_fallback': '$codec (see gsr.log)',
      'output': output.name,
      'output_why': pick.why,
      'geometry': output.geometry,
      if (window != null) 'window': rectText(window),
    });
  }

  void _append(_Active a, Marker m) {
    a.markers.add(m);
    File(p.join(a.dir.path, 'markers.jsonl'))
        .writeAsStringSync('${m.toLine()}\n', mode: FileMode.append);
  }

  /// Drops a [tag] marker now. [ask]: read a note through dmenu first.
  /// [hold]: keep it open until [note] closes it; returns its hold id.
  Future<int?> marker(MarkerTag tag, {bool ask = false, bool hold = false}) {
    final a = _active;
    if (a == null || a.stopping) {
      throw StateError('no session is recording');
    }
    final wall = parts.sys.nowUnix();
    final m = Marker(
      wallUnix: wall,
      offsetS: markerOffset(wall, a.t0),
      tag: tag,
    );
    unawaited(parts.overlay.mark(tag));
    if (hold) {
      final id = a.nextHold++;
      a.pending[id] = m;
      return Future.value(id);
    }
    if (ask) {
      a.asks.add(
        parts.asker.ask().then((text) => _append(a, m.copyWith(note: text))),
      );
      return Future.value();
    }
    _append(a, m);
    return Future.value();
  }

  /// Closes held marker [id] with [text]; false when there is none.
  bool note(int id, String text) {
    final a = _active;
    final m = a?.pending.remove(id);
    if (a == null || m == null) return false;
    _append(a, m.copyWith(note: text.split('\n').first.trim()));
    return true;
  }

  /// Ends the session (idempotent). [endedBy]: `button`, `hotkey`,
  /// `game-exit` or `recorder-exit`.
  Future<void> stop({String endedBy = 'button'}) async {
    final a = _active;
    if (a == null || a.stopping) return;
    a.stopping = true;
    parts.watcher.cancel();
    await parts.hotkeys.stop();
    await parts.overlay.stop();
    parts.asker.cancelAll();
    await Future.wait(a.asks);
    for (final m in a.pending.values) {
      _append(a, m);
    }
    a.pending.clear();
    await a.recording.stop();
    final meta = a.meta
      ..['state'] = 'stopped'
      ..['ended_by'] = endedBy
      ..['ended_unix'] = parts.sys.nowUnix();
    try {
      meta['duration_s'] = await parts.recorder.finish(
        a.recording,
        a.markers,
        a.t0,
      );
    } on Object catch (e) {
      meta['error'] = '$e';
      lastError = '$e';
    }
    parts.fps.finish(a.dir, a.t0, meta);
    parts.store.writeMeta(a.dir, meta);
    parts.log.event('record_stop', {
      'session': p.basename(a.dir.path),
      'ended_by': endedBy,
      'markers': a.markers.length,
      if (meta['error'] != null) 'error': meta['error'],
    });
    _active = null;
    if (!meta.containsKey('error')) await parts.analysis.launch(a.dir);
  }
}
