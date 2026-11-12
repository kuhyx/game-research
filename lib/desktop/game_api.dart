/// The per-game and document endpoints of the wrapper: the games list with
/// its finish state, the "research finished" launch, and the guarded
/// read/save of drafts and reports.
library;

import 'dart:io';

import 'package:game_research/core/slug.dart';
import 'package:game_research/desktop/doc_files.dart';
import 'package:game_research/desktop/game_store.dart';
import 'package:game_research/desktop/session_controller.dart';
import 'package:game_research/desktop/steam_library.dart';

/// A status code and a JSON body.
class ApiReply {
  /// Creates a reply.
  const new(this.status, this.body);

  /// HTTP status.
  final int status;

  /// JSON-encodable body.
  final Object? body;
}

ApiReply _err(int status, String why) => ApiReply(status, {'error': why});

/// Handlers that need no HTTP types.
class GameApi {
  /// Creates the handlers over [controller] and [library].
  new(this.controller, this.library)
    : docs = DocFiles(controller.parts.targets.list),
      games = GameStore(controller.parts.config);

  /// The session state machine (store, targets, analysis launcher).
  final SessionController controller;

  /// Installed games and their art.
  final SteamLibrary library;

  /// Guarded draft files.
  final DocFiles docs;

  /// Per-game finish state.
  final GameStore games;

  /// `/api/games`: each game, its slug, art flag and finish state.
  List<Map<String, Object?>> gamesJson() => [
    for (final g in library.games())
      {
        ...g.toJson(),
        'capsule': library.capsuleExpected(g.appid),
        'slug': slugify(g.name),
        'finish': games.finish(slugify(g.name)),
      },
  ];

  /// `GET /api/finish`: app id -> finish state, only for games that ran
  /// it. Polled by the page, so it reads two small files per game.
  Map<String, Object?> finishJson() => {
    for (final g in library.games())
      '${g.appid}': ?games.finish(slugify(g.name)),
  };

  /// `GET /api/doc?path=`.
  ApiReply read(String? path) {
    if (path == null || path.isEmpty) return _err(400, 'path needed');
    try {
      return ApiReply(200, {'text': docs.read(path)});
    } on DocDenied catch (e) {
      return _err(HttpStatus.forbidden, e.message);
    } on DocMissing {
      return _err(HttpStatus.notFound, 'no such document');
    }
  }

  /// `PUT /api/doc?path=` with the new [text].
  ApiReply save(String? path, String text) {
    if (path == null || path.isEmpty) return _err(400, 'path needed');
    try {
      docs.write(path, text);
      return const ApiReply(200, {'ok': true});
    } on DocDenied catch (e) {
      return _err(HttpStatus.forbidden, e.message);
    } on DocMissing {
      return _err(HttpStatus.notFound, 'no such document');
    }
  }

  /// `POST /api/games/<appid>/finish`: always records the request first
  /// (`finish.json`, state `queued`), then starts the job unless it already
  /// runs. The job waits behind the game's session analyses and the machine
  /// lock itself; a launch that fails leaves the request for the resume
  /// timer. Never refuses a known game.
  Future<ApiReply> finish(int appid) async {
    final game = library.find(appid);
    if (game == null) return _err(HttpStatus.notFound, 'no such game');
    final slug = slugify(game.name);
    final now = controller.parts.sys.nowUnix();
    final running = games.finish(slug)?['state'] == 'running';
    games.request(slug, appid, now);
    final started =
        !running && await controller.parts.analysis.launchFinish(slug);
    controller.parts.log.event('finish_request', {
      'appid': appid,
      'slug': slug,
      'started': started,
      'running': running,
    });
    return ApiReply(HttpStatus.accepted, {
      'ok': true,
      'slug': slug,
      'queued': true,
      'started': started,
    });
  }
}
