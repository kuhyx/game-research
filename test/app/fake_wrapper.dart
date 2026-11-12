import 'dart:async';
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

  /// Documents served by `/api/doc`, by absolute path.
  final docs = <String, String>{};

  /// Paths of documents that have a Discord version (`short` in `/api/doc`).
  final shorts = <String>{};

  /// Parts served by `/api/games/<id>/notes`.
  List<Map<String, Object?>> noteParts = [];

  /// When set, every copy POST waits for it.
  Completer<void>? copyGate;

  /// When true `/api/finish` is 404 (a wrapper without the finish job).
  bool noFinish = false;

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
    if (noFinish && path == '/api/finish') {
      return http.Response('{}', 404);
    }
    final docPath = r.url.queryParameters['path'];
    if (path == '/api/doc') {
      if (!docs.containsKey(docPath)) {
        return http.Response('{"error":"no such document"}', 404);
      }
      if (r.method == 'PUT') docs[docPath!] = r.body;
      final reply = {'text': docs[docPath], 'short': shorts.contains(docPath)};
      return http.Response(jsonEncode(reply), 200);
    }
    if (r.method == 'POST' && path.endsWith('/copy')) await copyGate?.future;
    final noteAt = RegExp(r'^/api/sessions/([^/]+)/markers/(\d+)/note$');
    final saved = noteAt.firstMatch(path);
    if (r.method == 'POST' && saved != null && postStatus == 200) {
      // The wrapper writes the note: the next read of the parts has it.
      for (final part in noteParts) {
        for (final m in part['markers']! as List) {
          final row = m as Map<String, Object?>;
          if (row['session'] == saved[1] && row['i'] == int.parse(saved[2]!)) {
            row['note'] = (jsonDecode(r.body) as Map)['note'];
          }
        }
      }
    }
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
        '/api/finish' => {
          for (final g in games)
            if (g['finish'] != null) '${g['appid']}': g['finish'],
        },
        '/api/targets' => {
          'current': '/src/cleanup-plate',
          'targets': [
            {'path': '/src/cleanup-plate', 'name': 'cleanup-plate'},
            {'path': '/src/other', 'name': 'other'},
          ],
        },
        '/api/sessions' => sessions,
        '/api/games/1/notes' => {'slug': 'one', 'parts': noteParts},
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
