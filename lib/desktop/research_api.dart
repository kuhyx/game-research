/// `/api/research`: add a blocked game as the research game (approved at
/// once, then Steam is asked to install it) and remove it again. Games
/// listing with each tile's enforcer lock lives here too.
library;

import 'dart:io';

import 'package:game_research/core/research_game.dart';
import 'package:game_research/core/slug.dart';
import 'package:game_research/core/steam.dart';
import 'package:game_research/desktop/game_api.dart';
import 'package:game_research/desktop/recording.dart';
import 'package:game_research/desktop/research_slot.dart';
import 'package:game_research/desktop/session_controller.dart';
import 'package:game_research/desktop/steam_library.dart';

/// The handlers.
class ResearchApi {
  /// Creates them over [controller] and [library].
  new(this.controller, this.library)
    : slot = ResearchSlot(controller.parts.config);

  /// The session state machine (launcher, log, clock).
  final SessionController controller;

  /// Installed games.
  final SteamLibrary library;

  /// The approval file and the enforcer.
  final ResearchSlot slot;

  /// Installed games first (as before), then every other owned game by
  /// name, each with its `lock` ([TileLock] name).
  List<Map<String, Object?>> games(List<Map<String, Object?>> installed) {
    final research = slot.appid;
    final allowed = slot.allowed();
    final seen = {for (final g in installed) g['appid']};
    String lock(int id, {required bool on}) => tileLock(
      appid: id,
      installed: on,
      allowed: allowed,
      research: research,
    ).name;
    final rest = [
      for (final e in slot.owned().entries)
        if (!seen.contains(e.key) && !isSteamTool(e.value)) e,
    ]..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return [
      for (final g in installed)
        {...g, 'lock': lock(g['appid']! as int, on: true)},
      for (final e in rest)
        {
          'appid': e.key,
          'name': e.value,
          'state': 'absent',
          'progress': 0,
          'capsule': library.capsuleExpected(e.key),
          'slug': slugify(e.value),
          'lock': lock(e.key, on: false),
        },
    ];
  }

  /// `POST /api/research?appid=`: 409 while another game holds the slot,
  /// 502 when the enforcer refuses (nothing is approved then).
  Future<ApiReply> add(int appid) async {
    final installed = library.find(appid) != null;
    if (!installed && !slot.owned().containsKey(appid)) {
      return const ApiReply(HttpStatus.notFound, {'error': 'no such game'});
    }
    final log = controller.parts.log;
    final now = controller.parts.sys.nowUnix();
    final result = await slot.add(appid, now: now);
    log.event('research_add', {'appid': appid, 'result': result.name});
    switch (result) {
      case ResearchAdd.taken:
        return const ApiReply(HttpStatus.conflict, {'error': 'slot taken'});
      case ResearchAdd.refused:
        return const ApiReply(HttpStatus.badGateway, {
          'error': 'the enforcer refused',
        });
      case ResearchAdd.added:
    }
    var install = false;
    if (!installed) {
      try {
        await controller.parts.launcher.launch(appid, uri: installUri(appid));
        install = true;
      } on StartError {
        // logged by the launcher; the tile stays absent, tapping retries
      }
    }
    return ApiReply(HttpStatus.ok, {
      'ok': true,
      'appid': appid,
      'install': install,
    });
  }

  /// `POST /api/research/remove`: revokes; sessions, stills and notes stay.
  Future<ApiReply> remove() async {
    final id = await slot.remove();
    controller.parts.log.event('research_remove', {'appid': id});
    return ApiReply(HttpStatus.ok, {'ok': true, 'appid': id});
  }
}
