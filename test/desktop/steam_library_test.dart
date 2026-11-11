import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/steam_library.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

String acf(int id, String name, {int flags = 4}) =>
    '"AppState"\n{\n\t"appid"\t\t"$id"\n\t"name"\t\t"$name"\n'
    '\t"StateFlags"\t\t"$flags"\n}\n';

void manifest(String steamapps, int id, String name, {int flags = 4}) {
  Directory(steamapps).createSync(recursive: true);
  File(p.join(steamapps, 'appmanifest_$id.acf'))
      .writeAsStringSync(acf(id, name, flags: flags));
}

void main() {
  late Directory root;
  late String steam;
  late SteamLibrary library;

  setUp(() {
    root = tempDir();
    steam = p.join(root.path, 'steam');
    library = SteamLibrary(steam);
  });

  test('no Steam root means no games', () {
    expect(library.games(), isEmpty);
    expect(library.find(1), isNull);
  });

  test('games: installed and updating, tools hidden, sorted, one per id', () {
    final apps = p.join(steam, 'steamapps');
    final second = p.join(root.path, 'second');
    manifest(apps, 20, 'beta');
    manifest(apps, 10, 'Alpha');
    manifest(apps, 30, 'Downloading', flags: 1026);
    manifest(apps, 40, 'Proton 9.0');
    File(p.join(apps, 'appmanifest_99.acf')).writeAsStringSync('garbage');
    File(p.join(apps, 'notes.txt')).writeAsStringSync('x');
    File(p.join(apps, 'appmanifest_5.txt')).writeAsStringSync(acf(5, 'Txt'));
    File(p.join(apps, 'libraryfolders.vdf')).writeAsStringSync(
      '"libraryfolders"\n{\n"0" { "path" "$steam" }\n'
      '"1" { "path" "$second" }\n"2" { "path" "${root.path}/gone" }\n}\n',
    );
    manifest(p.join(second, 'steamapps'), 50, 'Gamma');
    manifest(p.join(second, 'steamapps'), 20, 'beta in second');

    final games = library.games();
    expect(games.map((g) => g.name), ['Alpha', 'beta', 'Downloading', 'Gamma']);
    expect(games[2].installed, isFalse);
    expect(library.find(50)?.name, 'Gamma');
    expect(library.find(30)?.name, 'Downloading');
    expect(library.find(7), isNull);
  });

  group('capsule', () {
    late String cache;
    setUp(() => cache = p.join(steam, 'appcache', 'librarycache'));

    test('a known candidate file wins', () {
      Directory(p.join(cache, '7')).createSync(recursive: true);
      File(p.join(cache, '7', 'header.jpg')).writeAsStringSync('h');
      File(p.join(cache, '7', 'library_capsule.jpg')).writeAsStringSync('c');
      expect(library.capsule(7)?.path, endsWith('7/library_capsule.jpg'));
    });

    test('art one hashed folder deeper is found', () {
      final deep = Directory(p.join(cache, '8', 'abc123'))
        ..createSync(recursive: true);
      File(p.join(deep.path, 'logo.png')).writeAsStringSync('l');
      File(p.join(deep.path, 'library_600x900_en.jpg')).writeAsStringSync('x');
      expect(library.capsule(8)?.path, endsWith('library_600x900_en.jpg'));
    });

    test('nothing cached gives null', () {
      expect(library.capsule(9), isNull);
      final dir = Directory(p.join(cache, '9', 'h'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'logo.png')).writeAsStringSync('l');
      expect(library.capsule(9), isNull);
    });
  });
}
