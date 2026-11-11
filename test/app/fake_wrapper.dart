import 'dart:convert';

import 'package:game_research/app/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory wrapper API behind a MockClient, recording every call.
class FakeWrapper {
  /// Calls as `METHOD /path?query body`.
  final calls = <String>[];

  /// Game list served by `/api/games`.
  List<Map<String, Object?>> games = [
    {'appid': 1, 'name': 'One', 'capsule': true},
    {'appid': 2, 'name': 'Two', 'capsule': false},
  ];

  /// Whether a session records.
  bool recording = false;

  /// Error text in `/api/state`.
  String error = '';

  /// `phase` in `/api/state` while not recording.
  String phase = 'idle';

  /// Seconds the autostart ring lasts.
  double totalS = 3;

  /// Session rows served by `/api/sessions`.
  List<Map<String, Object?>> sessions = [];

  /// When true every request throws (wrapper offline).
  bool offline = false;

  /// Status code for POSTs (200 unless set).
  int postStatus = 200;

  /// Status code for GETs (200 unless set).
  int getStatus = 200;

  /// The API over this fake.
  ResearchApi api() =>
      ResearchApi(Uri.parse('http://127.0.0.1:1/'), MockClient(_handle));

  Future<http.Response> _handle(http.Request r) async {
    if (offline) throw http.ClientException('offline');
    final path = r.url.path;
    calls.add(
      '${r.method} $path${r.url.hasQuery ? '?${r.url.query}' : ''}'
      '${r.body.isEmpty ? '' : ' ${r.body}'}',
    );
    Object? body;
    if (r.method == 'GET') {
      body = switch (path) {
        '/api/state' => {
          'recording': recording,
          'error': error,
          'target': '/src/cleanup-plate',
          'phase': recording ? 'recording' : phase,
          if (const {'armed', 'launching', 'waiting'}.contains(phase))
            'pending': {
              'appid': 2,
              if (phase == 'armed') 'deadline_unix': 166.5,
              if (phase == 'armed') 'total_s': totalS,
            },
          if (recording)
            'session': {
              'id': 's1',
              'appid': 1,
              'started_unix': 100.0,
              'markers': {'good': 2},
            },
        },
        '/api/games' => games,
        '/api/targets' => {
          'current': '/src/cleanup-plate',
          'targets': [
            {'path': '/src/cleanup-plate', 'name': 'cleanup-plate'},
            {'path': '/src/other', 'name': 'other'},
          ],
        },
        '/api/sessions' => sessions,
        _ => null,
      };
      return http.Response(jsonEncode(body), body == null ? 404 : getStatus);
    }
    if (path == '/api/start') recording = true;
    if (path == '/api/stop') {
      recording = false;
      phase = 'idle';
    }
    if (path == '/api/autostart') phase = 'armed';
    if (path == '/api/autostart/cancel') phase = 'idle';
    final reply = path == '/api/marker'
        ? {'hold': r.url.queryParameters['hold'] == '1' ? 7 : null}
        : {'ok': true, if (postStatus != 200) 'error': 'nope'};
    return http.Response(jsonEncode(reply), postStatus);
  }
}
