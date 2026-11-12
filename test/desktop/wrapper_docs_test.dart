import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/steam_art.dart';
import 'package:path/path.dart' as p;

import '../support/server_harness.dart';

const _jpg = [0xFF, 0xD8, 0xFF, 0xE0, 9];

void main() {
  late ServerHarness s;

  Future<File> doc(String rel, [String text = '# hi']) async {
    final f = File(p.join(s.researchDir, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    return f;
  }

  String q(String path) => Uri.encodeQueryComponent(path);

  group('/api/doc', () {
    setUp(() async => s = await ServerHarness.start());

    test('GET returns the text of a draft under docs/research', () async {
      final f = await doc('games/g/DOCS-research-g-1.md', '# draft');
      final r = await s.hit('GET', '/api/doc?path=${q(f.path)}');
      expect(
        [r.status, r.json],
        [
          200,
          {'text': '# draft'},
        ],
      );
    });

    test('PUT saves the edited text to the same file', () async {
      final f = await doc('a.md');
      final r = await s.hit('PUT', '/api/doc?path=${q(f.path)}', body: 'new');
      expect(
        [r.status, r.json],
        [
          200,
          {'ok': true},
        ],
      );
      expect(f.readAsStringSync(), 'new');
      expect(s.h.events.last, 'api', reason: 'the save is logged');
    });

    test('unicode survives a save', () async {
      final f = await doc('a.md');
      await s.hit('PUT', '/api/doc?path=${q(f.path)}', body: 'zażółć ✓');
      expect(f.readAsStringSync(), 'zażółć ✓');
    });

    test(
      'outside docs/research and traversal are 403, nothing written',
      () async {
        final secret = File(p.join(s.h.root.path, 'secret.md'))
          ..writeAsStringSync('secret');
        final dotted = p.join(s.researchDir, '..', '..', '..', 'secret.md');
        for (final path in [secret.path, dotted, '/etc/passwd', 'a.md']) {
          final g = await s.hit('GET', '/api/doc?path=${q(path)}');
          expect(g.status, 403, reason: path);
          expect(g.body, isNot(contains('secret')));
          final put = await s.hit('PUT', '/api/doc?path=${q(path)}', body: 'x');
          expect(put.status, 403, reason: path);
        }
        expect(secret.readAsStringSync(), 'secret');
      },
    );

    test('missing path 400; missing file 404; wrong method 404', () async {
      expect((await s.hit('GET', '/api/doc')).status, 400);
      final gone = p.join(s.researchDir, 'gone.md');
      expect((await s.hit('GET', '/api/doc?path=${q(gone)}')).status, 404);
      expect(
        (await s.hit('PUT', '/api/doc?path=${q(gone)}', body: 'x')).status,
        404,
      );
      expect((await s.hit('POST', '/api/doc?path=${q(gone)}')).status, 404);
    });

    test('open-draft is gone: the panel reads the file itself', () async {
      expect((await s.hit('POST', '/api/sessions/x/open-draft')).status, 404);
    });
  });

  group('capsule art', () {
    test('a game with no art on disk is downloaded once and served', () async {
      final asked = <String>[];
      final root = Directory.systemTemp.createTempSync('gr_art');
      addTearDown(() => root.deleteSync(recursive: true));
      s = await ServerHarness.start(
        art: SteamArt(
          dir: p.join(root.path, 'art'),
          fetch: (url) async {
            asked.add(url.pathSegments.last);
            return url.pathSegments.last == 'library_600x900.jpg' ? _jpg : null;
          },
        ),
        games: {5: 'Five'},
      );
      final games = (await s.hit('GET', '/api/games')).json! as List;
      expect((games.single as Map)['capsule'], isTrue);
      final img = await s.hit('GET', '/api/capsule/5');
      expect([img.status, img.type], [200, 'image/jpeg']);
      await s.hit('GET', '/api/capsule/5');
      expect(asked, ['library_600x900.jpg']);
    });

    test('a failed download is 404 and not asked again', () async {
      var calls = 0;
      final root = Directory.systemTemp.createTempSync('gr_art');
      addTearDown(() => root.deleteSync(recursive: true));
      s = await ServerHarness.start(
        art: SteamArt(
          dir: p.join(root.path, 'art'),
          fetch: (_) async {
            calls++;
            return null;
          },
        ),
      );
      expect((await s.hit('GET', '/api/capsule/6')).status, 404);
      expect((await s.hit('GET', '/api/capsule/6')).status, 404);
      expect(calls, 2, reason: 'portrait + header once, then the miss cache');
    });
  });
}
