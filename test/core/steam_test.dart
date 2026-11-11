import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/steam.dart';

const _acf = '''
"AppState"
{
	"appid"		"1234560"
	"Universe"		"1"
	"name"		"Librarian: Tidy Up"
	"StateFlags"		"4"
	"installdir"		"Librarian"
	"UserConfig"
	{
		"name"		"nested must not win"
	}
}
''';

void main() {
  test('parseAcf reads appid, name and installdir at the top level', () {
    final g = parseAcf(_acf)!;
    expect(g.appid, 1234560);
    expect(g.name, 'Librarian: Tidy Up');
    expect(g.installed, isTrue);
    expect(g.toJson(), {
      'appid': 1234560,
      'name': 'Librarian: Tidy Up',
      'state': 'installed',
      'progress': 1.0,
    });
  });

  test('a manifest without appid or name is skipped', () {
    expect(parseAcf('"AppState" { "name" "x" }'), isNull);
    expect(parseAcf('"AppState" { "appid" "abc" "name" "x" }'), isNull);
    expect(parseAcf('"AppState" { "appid" "5" }'), isNull);
  });

  test('a manifest still downloading is not installed', () {
    final g = parseAcf(
      '"AppState" { "appid" "5" "name" "x" "StateFlags" "1026" }',
    );
    expect(g!.installed, isFalse);
    final noFlags = parseAcf('"AppState" { "appid" "5" "name" "x" }');
    expect(noFlags!.installed, isTrue);
  });

  test('the real interrupted Librarian manifest is an updating game', () {
    // Trimmed from kuhy's real appmanifest_4197610.acf (2026-11-11): Steam
    // quit mid-download, StateFlags 1026. Dropping it emptied the picker.
    final text = File('test/fixtures/appmanifest_4197610.acf')
        .readAsStringSync();
    final g = parseAcf(text)!;
    expect(g.appid, 4197610);
    expect(g.installed, isFalse);
    expect(g.progress, closeTo(1349071552 / 1873562816, 1e-9));
    expect(g.toJson(), {
      'appid': 4197610,
      'name': 'Librarian: Tidy Up the Arcane Library!',
      'state': 'updating',
      'progress': g.progress,
    });
  });

  test('Steam tools and runtimes are not games', () {
    for (final name in [
      'Proton 9.0',
      'Proton Experimental',
      'Steam Linux Runtime 3.0 (sniper)',
      'Steamworks Common Redistributables',
    ]) {
      expect(isSteamTool(name), isTrue, reason: name);
    }
    expect(isSteamTool('Librarian'), isFalse);
  });

  test('capsule candidates: per-app folder first, then flat names', () {
    final c = capsuleCandidates(42);
    expect(c.first, '42/library_600x900.jpg');
    expect(c, contains('42_library_600x900.jpg'));
    expect(c.last, '42_header.jpg');
  });

  test('libraryPaths reads every library path from libraryfolders.vdf', () {
    const vdf = '''
"libraryfolders"
{
	"0"
	{
		"path"		"/home/k/.local/share/Steam"
	}
	"1"
	{
		"path"		"/mnt/games/SteamLibrary"
	}
}
''';
    expect(libraryPaths(vdf), [
      '/home/k/.local/share/Steam',
      '/mnt/games/SteamLibrary',
    ]);
  });

  test('runGameUri is the steam rungameid uri', () {
    expect(runGameUri(7), 'steam://rungameid/7');
  });
}
