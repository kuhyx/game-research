import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/doc_files.dart';
import 'package:game_research/desktop/launcher.dart';
import 'package:game_research/desktop/steam_art.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';
import '../support/server_harness.dart';

void main() {
  late HttpServer server;
  late Uri base;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((req) async {
        switch (req.uri.path) {
          case '/ok':
            req.response.add([0xFF, 0xD8, 0xFF, 1]);
          case '/big':
            req.response.add(List.filled(3 * 1024 * 1024, 0xFF));
          default:
            req.response.statusCode = 404;
        }
        await req.response.close();
      }),
    );
  });

  group('httpArtFetch (loopback server, never the real CDN)', () {
    test('200 gives the bytes', () async {
      expect(await httpArtFetch(base.replace(path: '/ok')), [
        0xFF,
        0xD8,
        0xFF,
        1,
      ]);
    });

    test('404, an oversize body and a dead port give null', () async {
      expect(await httpArtFetch(base.replace(path: '/nope')), isNull);
      expect(await httpArtFetch(base.replace(path: '/big')), isNull);
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();
      expect(await httpArtFetch(Uri.parse('http://127.0.0.1:$port/x')), isNull);
    });
  });

  group('artOf', () {
    late Directory root;
    setUp(() => root = tempDir());

    test('test mode and ART=off never download', () {
      expect(artOf(testConfig(root)), isNull);
      final off = testConfig(
        root,
        extra: {'GAME_RESEARCH_TEST': '0', 'GAME_RESEARCH_ART': 'off'},
      );
      expect(artOf(off), isNull);
    });

    test('a real run caches under <data>/art', () {
      final real = testConfig(root, extra: {'GAME_RESEARCH_TEST': '0'});
      expect(artOf(real)?.dir, p.join(real.dataDir, 'art'));
    });
  });

  group('the 500 path', () {
    test('an unreadable document is a 500, not a crash', () async {
      final s = await ServerHarness.start();
      final f = File(p.join(s.researchDir, 'bad.md'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xFF, 0xFE, 0xFD]);
      final r = await s.hit(
        'GET',
        '/api/doc?path=${Uri.encodeQueryComponent(f.path)}',
      );
      expect(r.status, 500);
      expect(r.json, containsPair('error', isNotEmpty));
    });
  });

  test('document errors print their reason', () {
    expect(const DocDenied('why').toString(), 'why');
    expect(const DocMissing().toString(), contains('no such'));
  });
}
