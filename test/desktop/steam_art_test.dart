import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/steam_art.dart';
import 'package:game_research/desktop/steam_library.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const _jpg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];

void main() {
  late Directory root;
  late String cache;
  late Map<String, List<int>?> web;
  late List<String> asked;
  late double clock;
  late SteamArt art;
  late SteamLibrary library;

  setUp(() {
    root = tempDir();
    cache = p.join(root.path, 'steam', 'appcache', 'librarycache');
    web = {};
    asked = [];
    clock = 1000;
    art = SteamArt(
      dir: p.join(root.path, 'art'),
      fetch: (url) async {
        asked.add('$url');
        return web[url.pathSegments.last];
      },
      now: () => clock,
    );
    library = SteamLibrary(p.join(root.path, 'steam'), art: art);
  });

  File put(String rel) => File(p.join(cache, rel))
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  group('local layouts', () {
    test('the hashed library_capsule.jpg is the portrait (Librarian)', () {
      put('4197610/aaa/library_capsule.jpg');
      put('4197610/bbb/library_header.jpg');
      put('4197610/ccc/library_hero_blur.jpg');
      put('4197610/ddd.jpg');
      expect(
        library.capsule(4197610)?.path,
        endsWith('aaa/library_capsule.jpg'),
      );
    });

    test('portrait beats header beats the icon-sized top-level jpg', () {
      put('1/ddd.jpg');
      expect(library.capsule(1)?.path, endsWith('1/ddd.jpg'));
      put('1/bbb/library_header.jpg');
      expect(library.capsule(1)?.path, endsWith('library_header.jpg'));
      put('1/aaa/library_600x900_english.jpg');
      expect(library.capsule(1)?.path, endsWith('library_600x900_english.jpg'));
    });

    test('hero and logo files are not capsules', () {
      put('2/h/library_hero.jpg');
      put('2/l/logo.png');
      expect(library.capsule(2), isNull);
    });
  });

  group('download', () {
    test('no art on disk: CDN portrait, cached, no second fetch', () async {
      web['library_600x900.jpg'] = _jpg;
      final f = await library.art(5);
      expect(f?.path, p.join(root.path, 'art', '5.jpg'));
      expect(f?.readAsBytesSync(), _jpg);
      expect(
        asked.single,
        'https://shared.steamstatic.com/store_item_assets/steam/apps/5/'
        'library_600x900.jpg',
      );
      expect((await library.art(5))?.path, f?.path);
      expect(asked, hasLength(1));
      expect(library.capsuleExpected(5), isTrue);
    });

    test('a local portrait never touches the network', () async {
      put('6/x/library_capsule.jpg');
      expect((await library.art(6))?.path, endsWith('library_capsule.jpg'));
      expect(asked, isEmpty);
    });

    test('portrait missing: the header is fetched instead', () async {
      web['header.jpg'] = _jpg;
      final f = await library.art(7);
      expect(f?.readAsBytesSync(), _jpg);
      expect(asked.map((u) => u.split('/').last), [
        'library_600x900.jpg',
        'header.jpg',
      ]);
    });

    test('a miss is remembered for a day, then retried', () async {
      expect(await library.art(8), isNull);
      expect(asked, hasLength(2));
      expect(library.capsuleExpected(8), isFalse);
      expect(await library.art(8), isNull);
      expect(asked, hasLength(2), reason: 'negative cache');
      clock += 24 * 3600 + 1;
      expect(library.capsuleExpected(8), isTrue);
      web['library_600x900.jpg'] = _jpg;
      expect(await library.art(8), isNotNull);
    });

    test('non-JPEG bytes count as a miss', () async {
      web['library_600x900.jpg'] = [1, 2, 3];
      expect(await library.art(9), isNull);
      expect(File(p.join(root.path, 'art', '9.jpg')).existsSync(), isFalse);
    });

    test('local header is the fallback when the CDN has nothing', () async {
      put('10/h/library_header.jpg');
      expect((await library.art(10))?.path, endsWith('library_header.jpg'));
    });

    test('parallel asks share one download', () async {
      web['library_600x900.jpg'] = _jpg;
      await Future.wait([library.art(11), library.art(11)]);
      expect(asked, hasLength(1));
    });

    test('without a downloader only the disk is used', () async {
      final offline = SteamLibrary(p.join(root.path, 'steam'));
      expect(await offline.art(12), isNull);
      expect(offline.capsuleExpected(12), isFalse);
      expect(asked, isEmpty);
    });
  });
}
