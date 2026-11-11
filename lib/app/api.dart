/// The page's client for the wrapper's JSON API (same origin).
library;

import 'dart:convert';

import 'package:game_research/app/models.dart';
import 'package:http/http.dart' as http;

/// What the GUI needs from the wrapper.
class ResearchApi {
  /// Talks to the wrapper at [base] through [client].
  new(this.base, this.client);

  /// The wrapper's origin.
  final Uri base;

  /// HTTP client (a MockClient in tests).
  final http.Client client;

  Uri _u(String path, [Map<String, String>? query]) =>
      base.replace(path: '/api/$path', queryParameters: query);

  Future<Object?> _get(String path) async {
    final r = await client.get(_u(path));
    if (r.statusCode != 200) throw ApiError(r.statusCode, r.body);
    return jsonDecode(r.body);
  }

  Future<Map<String, Object?>> _post(
    String path, {
    Map<String, String>? query,
    String body = '',
  }) async {
    final r = await client.post(_u(path, query), body: body);
    final decoded = r.body.isEmpty ? null : jsonDecode(r.body);
    final json = decoded is Map<String, Object?>
        ? decoded
        : <String, Object?>{};
    if (r.statusCode >= 300) throw ApiError(r.statusCode, '${json['error']}');
    return json;
  }

  /// `/api/state`.
  Future<AppState> state() async =>
      AppState.fromJson((await _get('state'))! as Map<String, Object?>);

  /// Installed games.
  Future<List<Game>> games() async => [
    for (final g in (await _get('games'))! as List)
      Game.fromJson(g as Map<String, Object?>),
  ];

  /// Target projects.
  Future<TargetList> targets() async =>
      TargetList.fromJson((await _get('targets'))! as Map<String, Object?>);

  /// Past sessions, newest first.
  Future<List<SessionRow>> sessions() async => [
    for (final s in (await _get('sessions'))! as List)
      SessionRow.fromJson(s as Map<String, Object?>),
  ];

  /// The capsule image URL of [appid].
  String capsuleUrl(int appid) => _u('capsule/$appid').toString();

  /// Starts a session of [appid].
  Future<void> start(int appid) => _post('start', query: {'appid': '$appid'});

  /// Stops the session.
  Future<void> stop() => _post('stop');

  /// Drops a marker; [hold] keeps a note marker open and returns its id.
  Future<int?> marker(String tag, {bool hold = false}) async {
    final r = await _post(
      'marker',
      query: {'tag': tag, 'src': 'gui', if (hold) 'hold': '1'},
    );
    return r['hold'] as int?;
  }

  /// Closes held note marker [id] with [text].
  Future<void> note(int id, String text) =>
      _post('note', query: {'id': '$id'}, body: text);

  /// Picks the target project at [path].
  Future<void> pickTarget(String path) => _post('target', body: path);

  /// Reruns a session's analysis.
  Future<void> analyze(String id) => _post('sessions/$id/analyze');

  /// Opens a session's draft in the editor.
  Future<void> openDraft(String id) => _post('sessions/$id/open-draft');
}

/// A non-2xx answer.
class ApiError implements Exception {
  /// Creates the error.
  const new(this.status, this.message);

  /// HTTP status.
  final int status;

  /// The wrapper's error text.
  final String message;

  @override
  String toString() => 'ApiError $status: $message';
}
