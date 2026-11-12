/// The desktop half of the app: serves the web build and the JSON API the
/// page and the hotkeys call. Bound to loopback only: the endpoints start
/// processes and write files with no authentication.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:game_research/core/markers.dart';
import 'package:game_research/desktop/game_api.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/session_controller.dart';
import 'package:game_research/desktop/session_flow.dart';
import 'package:game_research/desktop/static_files.dart';
import 'package:game_research/desktop/steam_library.dart';

/// The HTTP server.
class WrapperServer {
  /// Creates the server.
  new({required this.webRoot, required this.flow})
    : api = GameApi(flow.controller, flow.library);

  /// The Flutter web build.
  final String webRoot;

  /// Autostart, launch, window wait, recording.
  final SessionFlow flow;

  /// The session state machine.
  SessionController get controller => flow.controller;

  /// Installed and updating games.
  SteamLibrary get library => flow.library;

  /// Games, finish and document endpoints.
  final GameApi api;
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
      // Every action is logged with its answer: a click that "did nothing"
      // shows up here with the status it got.
      if (req.method != 'GET') {
        controller.parts.log.event('api', {
          'path': req.uri.path,
          'query': req.uri.queryParameters,
          'status': res.statusCode,
        });
      }
      await res.close();
    }
  }

  void _json(HttpResponse res, Object? body, [int status = HttpStatus.ok]) {
    res
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
  }

  void _reply(HttpResponse res, ApiReply r) => _json(res, r.body, r.status);

  Future<void> _api(HttpRequest req, HttpResponse res, String path) async {
    final q = req.uri.queryParameters;
    final post = req.method == 'POST';
    final parts = path.split('/');
    final store = controller.parts.store;
    if (req.method == 'PUT' && path == 'doc') {
      final text = await utf8.decoder.bind(req).join();
      return _reply(res, api.save(q['path'], text));
    }
    switch ((post, parts)) {
      case (false, ['state']):
        _json(res, flow.state());
      case (false, ['games']):
        final games = api.gamesJson();
        controller.parts.log.event('picker', {
          'steam_root': library.steamRoot,
          'games': [
            for (final g in games) {...g}..remove('finish'),
          ],
        });
        _json(res, games);
      case (false, ['finish']):
        _json(res, api.finishJson());
      case (false, ['doc']):
        _reply(res, api.read(q['path']));
      case (true, ['games', final id, 'finish']):
        _reply(res, await api.finish(int.tryParse(id) ?? -1));
      case (false, ['capsule', final id]):
        final file = await library.art(int.tryParse(id) ?? -1);
        if (file == null) {
          res.statusCode = HttpStatus.notFound;
        } else {
          res.headers.contentType = ContentType('image', 'jpeg');
          await res.addStream(file.openRead());
        }
      case (true, ['start']):
        final id = int.tryParse(q['appid'] ?? '') ?? flow.lastAppid();
        try {
          await flow.start(id);
          _json(res, flow.state());
        } on StartError catch (e) {
          _json(res, {'error': e.message}, HttpStatus.conflict);
        }
      case (true, ['stop']):
        final by = q['src'] == 'key' ? 'hotkey' : 'button';
        if (flow.cancel(by)) return _json(res, flow.state());
        unawaited(controller.stop(endedBy: by));
        _json(res, {'stopping': controller.recording}, HttpStatus.accepted);
      case (true, ['autostart']):
        final ok = flow.arm(appid: int.tryParse(q['appid'] ?? ''));
        final nothingDue = ok || flow.skippedFinished;
        _json(
          res,
          flow.state(),
          nothingDue ? HttpStatus.ok : HttpStatus.conflict,
        );
      case (true, ['autostart', 'cancel']):
        final ok = flow.cancel(q['src'] ?? 'esc');
        _json(res, flow.state(), ok ? HttpStatus.ok : HttpStatus.conflict);
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
      default:
        _json(res, {'error': 'not found'}, HttpStatus.notFound);
    }
  }
}
