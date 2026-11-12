/// A [WrapperServer] over a [Harness], plus an HTTP client for it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/session_flow.dart';
import 'package:game_research/desktop/steam_art.dart';
import 'package:game_research/desktop/steam_library.dart';
import 'package:game_research/desktop/wrapper_server.dart';
import 'package:path/path.dart' as p;

import 'session_harness.dart';

/// One answer.
class Reply {
  /// Creates a reply.
  new(this.status, this.body, this.type);

  /// HTTP status.
  final int status;

  /// Body text.
  final String body;

  /// Content type.
  final String? type;

  /// Body as JSON.
  Object? get json => jsonDecode(body);
}

/// Server, client and a game manifest helper.
class ServerHarness {
  new _(this.h);

  /// Starts a server on a free port; closes it at test end.
  static Future<ServerHarness> start({
    SteamArt? art,
    Map<int, String> games = const {},
  }) async {
    HttpOverrides.global = null;
    final s = ServerHarness._(Harness());
    final web = Directory(p.join(s.h.root.path, 'web'))..createSync();
    File(p.join(web.path, 'index.html')).writeAsStringSync('<html>app</html>');
    s.server = WrapperServer(
      webRoot: web.path,
      flow: SessionFlow(
        s.h.controller,
        SteamLibrary(s.h.config.steamRoot, art: art),
        every: const Duration(milliseconds: 10),
      ),
    );
    s.port = await s.server.start(0);
    games.forEach(s.gameManifest);
    addTearDown(() async {
      s.client.close(force: true);
      await s.server.close();
    });
    return s;
  }

  /// The controller harness.
  final Harness h;

  /// The server under test.
  late final WrapperServer server;

  /// Its port.
  late final int port;

  /// The HTTP client.
  final client = HttpClient();

  /// One request.
  Future<Reply> hit(String method, String path, {String body = ''}) async {
    final req = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    if (body.isNotEmpty) req.add(utf8.encode(body));
    final res = await req.close();
    final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    final text = utf8.decode(bytes, allowMalformed: true);
    return Reply(res.statusCode, text, res.headers.contentType?.mimeType);
  }

  /// A Steam manifest for [id].
  void gameManifest(int id, String name) {
    final apps = Directory(p.join(h.config.steamRoot, 'steamapps'))
      ..createSync(recursive: true);
    File(p.join(apps.path, 'appmanifest_$id.acf')).writeAsStringSync(
      '"AppState"\n{\n"appid" "$id"\n"name" "$name"\n"StateFlags" "4"\n}\n',
    );
  }

  /// The default target's `docs/research` folder.
  String get researchDir => p.join(h.config.defaultTarget, 'docs', 'research');
}
