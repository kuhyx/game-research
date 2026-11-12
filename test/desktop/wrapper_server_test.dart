import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/session_flow.dart';
import 'package:game_research/desktop/steam_library.dart';
import 'package:game_research/desktop/wrapper_server.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';
import '../support/session_harness.dart';

class Reply {
  new(this.status, this.body, this.type);
  final int status;
  final String body;
  final String? type;
  Object? get json => jsonDecode(body);
}

void main() {
  late Harness h;
  late WrapperServer server;
  late SessionFlow flow;
  late HttpClient client;
  late int port;
  late Directory web;

  Future<Reply> hit(String method, String path, {String body = ''}) async {
    final req = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    if (body.isNotEmpty) req.write(body);
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    return Reply(res.statusCode, text, res.headers.contentType?.mimeType);
  }

  void gameManifest(int id, String name) {
    final apps = Directory(p.join(h.config.steamRoot, 'steamapps'))
      ..createSync(recursive: true);
    File(p.join(apps.path, 'appmanifest_$id.acf')).writeAsStringSync(
      '"AppState"\n{\n"appid" "$id"\n"name" "$name"\n"StateFlags" "4"\n}\n',
    );
  }

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    h = Harness();
    web = Directory(p.join(h.root.path, 'web'))..createSync();
    File(p.join(web.path, 'index.html')).writeAsStringSync('<html>app</html>');
    File(p.join(web.path, 'main.js')).writeAsStringSync('js');
    File(p.join(h.root.path, 'secret.txt')).writeAsStringSync('secret');
    gameManifest(730, 'Alpha');
    gameManifest(731, 'Beta');
    final cache = Directory(
      p.join(h.config.steamRoot, 'appcache', 'librarycache', '730'),
    )..createSync(recursive: true);
    File(p.join(cache.path, 'library_600x900.jpg')).writeAsStringSync('jpg');
    server = WrapperServer(
      webRoot: web.path,
      flow: flow = SessionFlow(
        h.controller,
        SteamLibrary(h.config.steamRoot),
        every: const Duration(milliseconds: 10),
      ),
    );
    port = await server.start(0);
    client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });
  });

  test('close before start is harmless', () async {
    await WrapperServer(webRoot: web.path, flow: flow).close();
  });

  test('static files: index, assets, 404, and no path escape', () async {
    final index = await hit('GET', '/');
    expect(
      [index.status, index.body, index.type],
      [200, '<html>app</html>', 'text/html'],
    );
    expect((await hit('GET', '/main.js')).type, 'text/javascript');
    expect((await hit('GET', '/nope.js')).status, 404);
    // Plain `..` is tidied by dart:io; an encoded slash reaches the guard.
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    socket.write('GET /..%2fsecret.txt HTTP/1.0\r\n\r\n');
    final raw = await utf8.decoder.bind(socket).join();
    expect(raw, startsWith('HTTP/1.0 403'));
    expect(raw, isNot(contains('secret\n')));
  });

  test('games list marks which have a cached capsule', () async {
    final games = (await hit('GET', '/api/games')).json! as List;
    const installed = {'state': 'installed', 'progress': 1.0};
    Map<String, Object?> none(String slug) => {'slug': slug, 'finish': null};
    expect(games, [
      {
        'appid': 730,
        'name': 'Alpha',
        ...installed,
        'capsule': true,
        ...none('alpha'),
      },
      {
        'appid': 731,
        'name': 'Beta',
        ...installed,
        'capsule': false,
        ...none('beta'),
      },
    ]);
    expect(h.events.last, 'picker');
  });

  test('capsule: the image, or 404', () async {
    final img = await hit('GET', '/api/capsule/730');
    expect([img.status, img.body, img.type], [200, 'jpg', 'image/jpeg']);
    expect((await hit('GET', '/api/capsule/731')).status, 404);
    expect((await hit('GET', '/api/capsule/abc')).status, 404);
  });

  test('state, and an unknown route', () async {
    final state = await hit('GET', '/api/state');
    expect(state.json, containsPair('recording', false));
    expect((await hit('GET', '/api/nothing')).status, 404);
    expect((await hit('POST', '/api/state')).status, 404);
  });

  test('start, markers, note, stop over HTTP', () async {
    final unknown = await hit('POST', '/api/start?appid=9');
    expect(unknown.status, 409);
    expect(unknown.json, {'error': 'game 9 is not in the Steam library'});
    expect((await hit('POST', '/api/start')).status, 409, reason: 'default');
    expect((await hit('POST', '/api/marker?tag=good')).status, 409);
    expect(h.events.last, 'api', reason: 'every POST is logged');

    final started = await hit('POST', '/api/start?appid=730');
    expect(started.status, 200);
    expect(started.json, containsPair('phase', 'waiting'));
    h.gameRuns(730);
    for (var i = 0; i < 100 && !h.controller.recording; i++) {
      await settle();
    }
    expect((await hit('POST', '/api/start?appid=731')).status, 409);

    expect((await hit('POST', '/api/marker?tag=zzz')).status, 409);
    expect((await hit('POST', '/api/marker?tag=good')).json, {'hold': null});
    expect((await hit('POST', '/api/marker?tag=bad&ask=1')).status, 200);
    final held = await hit('POST', '/api/marker?tag=note&hold=1');
    expect(held.json, {'hold': 1});

    expect((await hit('POST', '/api/note?id=7', body: 'x')).status, 404);
    final noted = await hit('POST', '/api/note?id=1', body: 'seen it\nmore');
    expect(
      [noted.status, noted.json],
      [
        200,
        {'ok': true},
      ],
    );

    final stop = await hit('POST', '/api/stop?src=key');
    expect(stop.status, 202);
    expect(stop.json, {'stopping': true});
    await h.untilStopped();
    expect(h.meta, containsPair('ended_by', 'hotkey'));
    final again = await hit('POST', '/api/stop');
    expect(again.status, 202);
    expect(again.json, {'stopping': false});
  });

  test('autostart: arm, refuse a second arm, cancel, stop cancels', () async {
    final armed = await hit('POST', '/api/autostart?appid=730');
    expect(armed.status, 200);
    expect(armed.json, containsPair('phase', 'armed'));
    expect((await hit('POST', '/api/autostart')).status, 409);
    final cancel = await hit('POST', '/api/autostart/cancel?src=cli');
    expect(cancel.json, containsPair('phase', 'idle'));
    expect((await hit('POST', '/api/autostart/cancel')).status, 409);
    await hit('POST', '/api/autostart?appid=730');
    final stop = await hit('POST', '/api/stop');
    expect([stop.status, flow.phase], [200, Phase.idle]);
  });

  test('targets: list and pick', () async {
    final list = (await hit('GET', '/api/targets')).json! as Map;
    expect(list['current'], h.config.defaultTarget);
    final bad = await hit('POST', '/api/target', body: '/nowhere');
    expect(bad.status, 404);
    final good = await hit(
      'POST',
      '/api/target',
      body: ' ${h.config.defaultTarget}\n',
    );
    expect(good.status, 200);
  });

  test('sessions: list, analyze and its errors', () async {
    final dir = Directory(p.join(h.config.dataDir, '2026-s'))
      ..createSync(recursive: true);
    h.parts.store.writeMeta(dir, {'appid': 730});
    final list = (await hit('GET', '/api/sessions')).json! as List;
    expect(list.single, containsPair('id', '2026-s'));

    expect((await hit('POST', '/api/sessions/none/analyze')).status, 404);
    final ran = await hit('POST', '/api/sessions/2026-s/analyze');
    expect(
      [ran.status, ran.json],
      [
        200,
        {'ok': true},
      ],
    );
    expect(h.fake.calls.last.args, [dir.path], reason: 'resume, not redo');
    Directory(p.join(dir.path, 'analysis')).createSync();
    File(p.join(dir.path, 'analysis', 'status.json')).writeAsStringSync(
      jsonEncode({'stage': 3, 'done': 1, 'total': 1, 'state': 'done'}),
    );
    await hit('POST', '/api/sessions/2026-s/analyze');
    expect(h.fake.calls.last.args, [dir.path, '--force']);
    h.fake.onStart = (_) => throw const ProcessException('x', []);
    expect((await hit('POST', '/api/sessions/2026-s/analyze')).status, 503);

    expect((await hit('POST', '/api/sessions/2026-s/frobnicate')).status, 404);
  });
}
