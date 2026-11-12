/// The HTTP routes that hand kuhy's marker notes and stills to a Discord DM:
/// the notes of a game cut into message parts, a still as an image, and
/// "copy" actions that put a part, a single marker or the Discord version of
/// a document on the clipboard.
///
/// Only text kuhy typed is offered. Copying is refused while a session
/// records (the helper and the stills must not compete with the game).
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/discord_notes.dart';
import 'package:game_research/core/share_contract.dart';
import 'package:game_research/core/slug.dart';
import 'package:game_research/core/steam.dart';
import 'package:game_research/desktop/clip_owner.dart';
import 'package:game_research/desktop/doc_files.dart';
import 'package:game_research/desktop/notes_api.dart';
import 'package:game_research/desktop/session_controller.dart';
import 'package:game_research/desktop/share_stage.dart';
import 'package:game_research/desktop/steam_library.dart';

/// Notes, stills and copy endpoints.
class ShareRoutes {
  /// Creates the routes over [controller]'s session folders.
  new(this.controller, this.library)
    : notes = NotesApi(
        controller.parts.config,
        controller.parts.sys,
        controller.parts.store,
        controller.parts.log,
      ),
      clip = ClipOwner(controller.parts.config, controller.parts.sys),
      docs = DocFiles(controller.parts.targets.list);

  /// The session state machine (is a session recording?).
  final SessionController controller;

  /// Installed games.
  final SteamLibrary library;

  /// Notes and stills on disk.
  final NotesApi notes;

  /// The clipboard.
  final ClipOwner clip;

  /// Guarded draft files (their Discord versions).
  final DocFiles docs;

  /// Answers [req] when it is one of the share routes; false = not ours.
  /// [parts] is the path below `/api/`.
  Future<bool> handle(
    HttpRequest req,
    HttpResponse res,
    List<String> parts,
  ) async {
    final what = req.uri.queryParameters['what'];
    switch ((req.method, parts)) {
      case ('GET', ['games', final id, 'notes']):
        await _notes(res, id);
      case ('GET', ['sessions', final id, 'still', final i]):
        await _still(res, id, i);
      case ('POST', ['games', final id, 'notes', final n, 'copy']):
        await _copyPart(res, id, n, what);
      case ('POST', ['sessions', final id, 'markers', final i, 'note']):
        await _saveNote(req, res, id, i);
      case ('POST', ['sessions', final id, 'markers', final i, 'copy']):
        await _copyMarker(res, id, i);
      case ('POST', ['doc', 'copy']):
        await _copyDoc(res, req.uri.queryParameters['path']);
      default:
        return false;
    }
    return true;
  }

  void _json(HttpResponse res, Object? body, [int status = HttpStatus.ok]) {
    res
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
  }

  void _err(HttpResponse res, int status, String why) =>
      _json(res, {'error': why}, status);

  SteamGame? _game(String id) => library.find(int.tryParse(id) ?? -1);

  Future<void> _notes(HttpResponse res, String id) async {
    final game = _game(id);
    if (game == null) return _err(res, HttpStatus.notFound, 'no such game');
    _json(res, notes.notes(slugify(game.name), game.name));
  }

  Future<void> _still(HttpResponse res, String id, String i) async {
    final file = notes.stillFile(id, int.tryParse(i) ?? -1);
    if (file == null) return _err(res, HttpStatus.notFound, 'no such still');
    res.headers.contentType = ContentType('image', 'jpeg');
    await res.addStream(file.openRead());
  }

  Future<void> _copyPart(
    HttpResponse res,
    String id,
    String n,
    String? what,
  ) async {
    final game = _game(id);
    if (game == null) return _err(res, HttpStatus.notFound, 'no such game');
    if (what != 'files' && what != 'text') {
      return _err(res, HttpStatus.badRequest, 'what=files|text');
    }
    final all = notes.parts(slugify(game.name), game.name);
    final k = int.tryParse(n) ?? -1;
    if (k < 1 || k > all.length) {
      return _err(res, HttpStatus.notFound, 'no such part');
    }
    final part = all[k - 1];
    if (part.markers.any((m) => m.note.isEmpty)) {
      return _err(res, HttpStatus.conflict, 'a marker has no note');
    }
    if (what == 'text') return await _copy(res, const [], part.text);
    // Discord pairs images with note lines by order only, so a part with a
    // missing still is not copied at all.
    final cut = [for (final m in part.markers) notes.still(m)];
    if (cut.contains(null)) {
      return _err(res, HttpStatus.conflict, 'stills not all cut yet');
    }
    if (controller.recording) {
      return _err(res, HttpStatus.conflict, 'a session is recording');
    }
    final List<String> files;
    try {
      files = await stageStills(
        controller.parts.sys,
        controller.parts.config,
        '${slugify(game.name)}-$k',
        [
          for (var i = 0; i < cut.length; i++)
            _source(cut[i]!, part.markers[i], game.name),
        ],
      );
    } on CaptionFailed catch (e) {
      return _err(res, HttpStatus.internalServerError, e.message);
    }
    await _copy(res, files, part.text);
  }

  /// kuhy's note of one marker, from the body `{"note": "..."}`.
  Future<void> _saveNote(
    HttpRequest req,
    HttpResponse res,
    String id,
    String i,
  ) async {
    final body = await utf8.decoder.bind(req).join();
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return _err(res, HttpStatus.badRequest, 'json {note} needed');
    }
    final raw = json is Map ? json['note'] : null;
    final note = raw is String ? raw.split('\n').first.trim() : '';
    if (note.isEmpty) return _err(res, HttpStatus.badRequest, 'empty note');
    final session = controller.state()['session'];
    if (session is Map && session['id'] == id) {
      return _err(res, HttpStatus.conflict, 'a session is recording');
    }
    if (!notes.setNote(id, int.tryParse(i) ?? -1, note)) {
      return _err(res, HttpStatus.notFound, 'no such marker');
    }
    _json(res, {'ok': true});
  }

  Future<void> _copyMarker(HttpResponse res, String id, String i) async {
    final k = int.tryParse(i) ?? -1;
    final file = notes.stillFile(id, k);
    final entry = notes.markerEntry(id, k);
    if (file == null || entry == null) {
      return _err(res, HttpStatus.notFound, 'no such still');
    }
    if (entry.note.isEmpty) {
      return _err(res, HttpStatus.conflict, 'the marker has no note');
    }
    if (controller.recording) {
      return _err(res, HttpStatus.conflict, 'a session is recording');
    }
    final game = notes.gameOf(id);
    final List<String> files;
    try {
      files = await stageStills(
        controller.parts.sys,
        controller.parts.config,
        'marker-$id-$k',
        [_source(file, entry, game)],
      );
    } on CaptionFailed catch (e) {
      return _err(res, HttpStatus.internalServerError, e.message);
    }
    await _copy(res, files, entry.line);
  }

  StillSource _source(File file, NoteLine m, String game) => (
    source: file,
    tag: m.tag.name,
    time: m.time,
    note: m.note,
    right: '$game · ${sessionDate(m.session)}',
  );

  /// The Discord version of the document at [path], text only.
  Future<void> _copyDoc(HttpResponse res, String? path) async {
    if (path == null || path.isEmpty) {
      return _err(res, HttpStatus.badRequest, 'path needed');
    }
    final String? text;
    try {
      text = docs.readShort(path);
    } on DocDenied catch (e) {
      return _err(res, HttpStatus.forbidden, e.message);
    } on DocMissing {
      return _err(res, HttpStatus.notFound, 'no such document');
    }
    if (text == null) return _err(res, HttpStatus.notFound, 'no short version');
    await _copy(res, const [], text);
  }

  Future<void> _copy(HttpResponse res, List<String> files, String text) async {
    if (controller.recording) {
      return _err(res, HttpStatus.conflict, 'a session is recording');
    }
    try {
      await clip.copy(files: files, text: text);
    } on NoDisplay catch (e) {
      return _err(res, HttpStatus.conflict, e.message);
    } on ClipFailed catch (e) {
      return _err(res, HttpStatus.internalServerError, e.message);
    }
    _json(res, {'ok': true, 'files': files.length, 'chars': text.length});
  }
}
