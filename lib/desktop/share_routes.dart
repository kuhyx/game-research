/// The HTTP routes that hand kuhy's marker notes and stills to a Discord DM:
/// the notes of a game cut into message parts, a still as an image, and
/// "copy" actions that put a part or a single marker on the clipboard.
///
/// Only text kuhy typed is offered. Copying is refused while a session
/// records (the helper and the stills must not compete with the game).
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/slug.dart';
import 'package:game_research/core/steam.dart';
import 'package:game_research/desktop/clip_owner.dart';
import 'package:game_research/desktop/notes_api.dart';
import 'package:game_research/desktop/session_controller.dart';
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
      clip = ClipOwner(controller.parts.config, controller.parts.sys);

  /// The session state machine (is a session recording?).
  final SessionController controller;

  /// Installed games.
  final SteamLibrary library;

  /// Notes and stills on disk.
  final NotesApi notes;

  /// The clipboard.
  final ClipOwner clip;

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
      case ('POST', ['sessions', final id, 'markers', final i, 'copy']):
        await _copyMarker(res, id, i);
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
    final files = what == 'files'
        ? [
            for (final m in part.markers)
              if (notes.still(m) case final f?) f.path,
          ]
        : <String>[];
    if (what == 'files' && files.isEmpty) {
      return _err(res, HttpStatus.notFound, 'no stills cut yet');
    }
    await _copy(res, files, part.text);
  }

  Future<void> _copyMarker(HttpResponse res, String id, String i) async {
    final k = int.tryParse(i) ?? -1;
    final file = notes.stillFile(id, k);
    final line = notes.markerLine(id, k);
    if (file == null || line == null) {
      return _err(res, HttpStatus.notFound, 'no such still');
    }
    await _copy(res, [file.path], line);
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
