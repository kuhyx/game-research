/// The desktop half of the app: serves the web build and the JSON API the
/// page and the hotkeys call. Bound to loopback only: the endpoints start
/// processes and write files with no authentication.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/markers.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/desktop/session_controller.dart';
import 'package:game_research/desktop/static_files.dart';
import 'package:game_research/desktop/steam_library.dart';

/// Opens a file in kuhy's editor (xdg-open). Replaced in tests.
typedef FileOpener = Future<void> Function(String path);

/// The HTTP server.
class WrapperServer {
  /// Creates the server.
  new({
    required this.webRoot,
    required this.controller,
    required this.library,
    required this.open,
  });

  /// The Flutter web build.
  final String webRoot;

  /// The session state machine.
  final SessionController controller;

  /// Installed games.
  final SteamLibrary library;

  /// Opens a draft.
  final FileOpener open;
  HttpServer? _server;

  /// Listens on loopback [port] (0 = any, for tests); returns the port.
  Future<int> start(int port) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(_handle);
    return server.port;
  }

  /// Stops listening.
  Future<void> close() async {
    await _server?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final path = req.uri.path;
      if (!path.startsWith('/api/')) {
        await serveStatic(res, webRoot, req.uri.pathSegments);
      } else {
        res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        await _api(req, res, path.substring('/api/'.length));
      }
    } on Object catch (e) {
      _json(res, {'error': '$e'}, HttpStatus.internalServerError);
    } finally {
      await res.close();
    }
  }

  void _json(HttpResponse res, Object? body, [int status = HttpStatus.ok]) {
    res
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
  }

  Future<void> _api(HttpRequest req, HttpResponse res, String path) async {
    final q = req.uri.queryParameters;
    final post = req.method == 'POST';
    final parts = path.split('/');
    final store = controller.parts.store;
    switch ((post, parts)) {
      case (false, ['state']):
        _json(res, controller.state());
      case (false, ['games']):
        _json(res, [
          for (final g in library.games())
            {...g.toJson(), 'capsule': library.capsule(g.appid) != null},
        ]);
      case (false, ['capsule', final id]):
        final file = library.capsule(int.tryParse(id) ?? -1);
        if (file == null) {
          res.statusCode = HttpStatus.notFound;
        } else {
          res.headers.contentType = ContentType('image', 'jpeg');
          await res.addStream(file.openRead());
        }
      case (true, ['start']):
        final game = library.find(int.tryParse(q['appid'] ?? '') ?? -1);
        if (game == null) {
          return _json(res, {'error': 'unknown game'}, HttpStatus.notFound);
        }
        try {
          await controller.start(game);
          _json(res, controller.state());
        } on Exception catch (e) {
          _json(res, {'error': '$e'}, HttpStatus.conflict);
        }
      case (true, ['stop']):
        final by = q['src'] == 'key' ? 'hotkey' : 'button';
        unawaited(controller.stop(endedBy: by));
        _json(res, {'stopping': controller.recording}, HttpStatus.accepted);
      case (true, ['marker']):
        final tag = MarkerTag.tryParse(q['tag']);
        if (tag == null || !controller.recording) {
          return _json(res, {'error': 'no marker'}, HttpStatus.conflict);
        }
        final hold = await controller.marker(
          tag,
          ask: q['ask'] == '1',
          hold: q['hold'] == '1',
        );
        _json(res, {'hold': hold});
      case (true, ['note']):
        final text = await utf8.decoder.bind(req).join();
        final ok = controller.note(int.tryParse(q['id'] ?? '') ?? -1, text);
        _json(res, {'ok': ok}, ok ? HttpStatus.ok : HttpStatus.notFound);
      case (false, ['targets']):
        _json(res, controller.parts.targets.toJson());
      case (true, ['target']):
        final target = await utf8.decoder.bind(req).join();
        final ok = controller.parts.targets.pick(target.trim());
        _json(
          res,
          controller.parts.targets.toJson(),
          ok ? 200 : HttpStatus.notFound,
        );
      case (false, ['sessions']):
        _json(res, store.list());
      case (true, ['sessions', final id, final action]):
        final dir = store.dir(id);
        if (dir == null) {
          return _json(res, {'error': 'no session'}, HttpStatus.notFound);
        }
        if (action == 'analyze') {
          // Resume a failed or unfinished job; redo a finished one.
          final done = store.status(dir).state == StageState.done;
          final ok = await controller.parts.analysis.launch(dir, force: done);
          _json(res, {'ok': ok}, ok ? 200 : HttpStatus.serviceUnavailable);
        } else if (action == 'open-draft') {
          final draft = store.summary(dir)['draft'] as String?;
          if (draft == null) {
            return _json(res, {'error': 'no draft'}, HttpStatus.notFound);
          }
          await open(draft);
          _json(res, {'ok': true});
        } else {
          _json(res, {'error': 'unknown action'}, HttpStatus.notFound);
        }
      default:
        _json(res, {'error': 'not found'}, HttpStatus.notFound);
    }
  }
}
