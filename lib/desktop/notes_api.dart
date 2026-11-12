/// kuhy's marker notes per game, read from the session folders, plus the
/// stills that go with them. Sessions recorded before stills existed get
/// theirs cut lazily, in the background, one ffmpeg at a time and never
/// while a recording runs (the game must not compete with ffmpeg).
library;

import 'dart:async';
import 'dart:io';

import 'package:game_research/analysis/stills.dart' as stills;
import 'package:game_research/core/discord_notes.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/slug.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/recording_flag.dart';
import 'package:game_research/desktop/session_store.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// Notes and stills of the games on disk.
class NotesApi {
  /// Creates the reader over [store]; extraction goes through [sys].
  new(this.config, this.sys, this.store, this.log)
    : _flag = RecordingFlag(config.dataDir, procRoot: config.procRoot);

  /// Settings.
  final Config config;

  /// OS seam (ffmpeg).
  final Sys sys;

  /// Session folders.
  final SessionStore store;

  /// Event log.
  final EventLog log;

  final RecordingFlag _flag;
  final _queued = <String>{};
  Future<void> _queue = Future.value();

  /// Completes when the extractions queued so far are done.
  Future<void> get idle => _queue;

  List<Marker> _markers(Directory dir) {
    final file = File(p.join(dir.path, 'markers.jsonl'));
    return file.existsSync() ? parseMarkers(file.readAsStringSync()) : [];
  }

  DateTime _started(Directory dir, Map<String, Object?> meta) {
    final unix = meta['started_unix'];
    if (unix is num) {
      return DateTime.fromMillisecondsSinceEpoch((unix * 1000).round());
    }
    return File(p.join(dir.path, 'session.json')).lastModifiedSync();
  }

  /// Every session of game [slug] (analysed or not), with its folder.
  List<(Directory, NoteSession)> _sessions(String slug) {
    final root = Directory(config.dataDir);
    if (!root.existsSync()) return const [];
    final found = <(Directory, NoteSession)>[];
    for (final dir in root.listSync().whereType<Directory>()) {
      if (!File(p.join(dir.path, 'session.json')).existsSync()) continue;
      final meta = store.meta(dir);
      if (slugify('${meta['game']}') != slug) continue;
      found.add((
        dir,
        NoteSession(
          id: p.basename(dir.path),
          started: _started(dir, meta),
          markers: _markers(dir),
        ),
      ));
    }
    return found;
  }

  /// The message parts of game [name] (slug [slug]), oldest session first.
  /// Also queues the missing stills.
  List<NotePart> parts(String slug, String name) {
    final found = _sessions(slug);
    for (final (dir, s) in found) {
      _queueStills(dir, s.markers);
    }
    return buildParts(name, [for (final (_, s) in found) s]);
  }

  /// `GET /api/games/<appid>/notes` body.
  Map<String, Object?> notes(String slug, String name) => {
    'slug': slug,
    'parts': [
      for (final part in parts(slug, name))
        {
          'n': part.n,
          'of': part.of,
          'text': part.text,
          'markers': [
            for (final m in part.markers)
              {
                'session': m.session,
                'i': m.i,
                'tag': m.tag.name,
                'time': m.time,
                'note': m.note,
                'line': m.line,
                'still': still(m) != null,
              },
          ],
        },
    ],
  };

  /// The still of [line], or null while it is not cut.
  File? still(NoteLine line) {
    final dir = store.dir(line.session);
    if (dir == null) return null;
    final file = stills.stillFile(dir.path, line.i, line.tag);
    return file.existsSync() ? file : null;
  }

  /// The still of marker [i] (1-based) of session [id], or null.
  File? stillFile(String id, int i) {
    final marker = _marker(id, i);
    final dir = store.dir(id);
    if (marker == null || dir == null) return null;
    final file = stills.stillFile(dir.path, i, marker.tag);
    return file.existsSync() ? file : null;
  }

  /// The game name recorded in session [id] ('' when unknown).
  String gameOf(String id) {
    final dir = store.dir(id);
    return dir == null ? '' : '${store.meta(dir)['game'] ?? ''}';
  }

  /// The note line of marker [i] of session [id], or null.
  NoteLine? markerEntry(String id, int i) {
    final marker = _marker(id, i);
    final dir = store.dir(id);
    if (marker == null || dir == null) return null;
    final started = _started(dir, store.meta(dir));
    return buildParts('', [
      NoteSession(id: id, started: started, markers: [marker]),
    ]).single.markers.single;
  }

  /// The text line of marker [i] of session [id], or null.
  String? markerLine(String id, int i) => markerEntry(id, i)?.line;

  Marker? _marker(String id, int i) {
    final dir = store.dir(id);
    if (dir == null) return null;
    final markers = _markers(dir);
    return i < 1 || i > markers.length ? null : markers[i - 1];
  }

  void _queueStills(Directory dir, List<Marker> markers) {
    final id = p.basename(dir.path);
    if (markers.isEmpty ||
        _queued.contains(id) ||
        _flag.live ||
        !File(p.join(dir.path, 'recording.mkv')).existsSync() ||
        stills.stillsComplete(dir.path, markers)) {
      return;
    }
    _queued.add(id);
    _queue = _queue.then((_) async {
      try {
        final made = await stills.extractStills(sys, dir.path, markers);
        log.event('stills', {'session': id, 'made': made.length});
      } on Object catch (e) {
        log.event('stills', {'session': id, 'error': '$e'});
      } finally {
        _queued.remove(id);
      }
    });
  }
}
