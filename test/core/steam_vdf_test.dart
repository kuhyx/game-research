import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/steam_vdf.dart';

const conf = '/home/k/data/game-research/mangohud.conf';
const mango = 'MANGOHUD=1 MANGOHUD_CONFIGFILE=$conf';

/// A trimmed `localconfig.vdf` with [apps] as the body of `"apps"`.
String vdf(String apps) =>
    '''
"UserLocalConfigStore"
{
\t"Software"
\t{
\t\t"Valve"
\t\t{
\t\t\t"Steam"
\t\t\t{
\t\t\t\t"apps"
\t\t\t\t{
$apps\t\t\t\t}
\t\t\t}
\t\t}
\t}
\t"friends"
\t{
\t\t"PersonaName"\t\t"k {\\"x\\"}"
\t}
}
''';

const withOptions = '''
\t\t\t\t\t"4197610"
\t\t\t\t\t{
\t\t\t\t\t\t"LastPlayed"\t\t"1762850000"
\t\t\t\t\t\t"LaunchOptions"\t\t"-novid"
\t\t\t\t\t}
''';

void main() {
  group('setLaunchOption', () {
    test('replaces an existing value and keeps the rest byte for byte', () {
      final out = setLaunchOption(vdf(withOptions), 4197610, 'X')!;
      expect(out, vdf(withOptions.replaceFirst('"-novid"', '"X"')));
    });

    test('adds the key to an app block that lacks it', () {
      const app = '''
\t\t\t\t\t"4197610"
\t\t\t\t\t{
\t\t\t\t\t\t"LastPlayed"\t\t"1762850000"
\t\t\t\t\t}
''';
      final out = setLaunchOption(vdf(app), 4197610, 'X')!;
      expect(
        out,
        vdf(
          app.replaceFirst(
            '\t\t\t\t\t}\n',
            '\t\t\t\t\t\t"LaunchOptions"\t\t"X"\n\t\t\t\t\t}\n',
          ),
        ),
      );
    });

    test('adds the app block to an apps block without it', () {
      const other = '''
\t\t\t\t\t"220"
\t\t\t\t\t{
\t\t\t\t\t\t"LaunchOptions"\t\t"keep"
\t\t\t\t\t}
''';
      final out = setLaunchOption(vdf(other), 4197610, 'X')!;
      expect(out, contains('"LaunchOptions"\t\t"keep"'));
      expect(
        out,
        vdf(
          '$other\t\t\t\t\t"4197610"\n\t\t\t\t\t{\n'
          '\t\t\t\t\t\t"LaunchOptions"\t\t"X"\n\t\t\t\t\t}\n',
        ),
      );
    });

    test('adds the app block to an empty apps block', () {
      final out = setLaunchOption(vdf(''), 7, 'X')!;
      expect(
        out,
        vdf(
          '\t\t\t\t\t"7"\n\t\t\t\t\t{\n'
          '\t\t\t\t\t\t"LaunchOptions"\t\t"X"\n\t\t\t\t\t}\n',
        ),
      );
    });

    test('escapes quotes and backslashes, reads them back', () {
      final out = setLaunchOption(vdf(withOptions), 4197610, r'A="b\c"')!;
      expect(out, contains(r'"A=\"b\\c\""'));
      expect(launchOption(out, 4197610), r'A="b\c"');
    });

    test('matches keys case-insensitively and skips // comments', () {
      const text = '''
// header
"userlocalconfigstore" { "SOFTWARE" { "valve" { "STEAM" { "Apps" {
  "5" { "launchoptions" "old" }
} } } } }
''';
      final out = setLaunchOption(text, 5, 'new')!;
      expect(out, contains('"launchoptions" "new"'));
      expect(launchOption(out, 5), 'new');
    });

    test('reads unquoted tokens', () {
      const text =
          'UserLocalConfigStore { Software { Valve { Steam { apps '
          '{ 5 { LaunchOptions old } 6 { x y } } } } } }';
      expect(launchOption(text, 5), 'old');
      expect(launchOption(text, 6), isNull);
      expect(launchOption(text, 7), isNull);
      expect(launchOption('"a" {}', 5), isNull);
    });

    test('throws on text without an apps block', () {
      expect(() => setLaunchOption('', 1, 'X'), throwsFormatException);
      expect(
        () => setLaunchOption('"UserLocalConfigStore"\n{\n}\n', 1, 'X'),
        throwsFormatException,
      );
    });

    test('throws on a key without value and on a stray brace', () {
      expect(
        () => setLaunchOption('"UserLocalConfigStore" { "a" }', 1, 'X'),
        throwsFormatException,
      );
      expect(() => launchOption('}', 1), throwsFormatException);
      expect(() => launchOption('"a" { { }', 1), throwsFormatException);
    });

    test(r'reads \n and \t escapes', () {
      final text = vdf(withOptions.replaceFirst('-novid', r'a\nb\tc'));
      expect(launchOption(text, 4197610), 'a\nb\tc');
    });

    test('throws on an unterminated block or string', () {
      expect(
        () => setLaunchOption('"UserLocalConfigStore" {', 1, 'X'),
        throwsFormatException,
      );
      expect(
        () => setLaunchOption('"UserLocalConfigStore', 1, 'X'),
        throwsFormatException,
      );
    });

    test('inserts into a one-line app block', () {
      final text = vdf('\t\t\t\t\t"9" {}\n');
      final out = setLaunchOption(text, 9, 'X')!;
      expect(launchOption(out, 9), 'X');
    });

    test('null when the value is already there', () {
      expect(setLaunchOption(vdf(withOptions), 4197610, '-novid'), isNull);
    });
  });

  group('mangoOptions', () {
    test('empty options get the env and %command%', () {
      expect(mangoOptions('', conf), '$mango %command%');
      expect(mangoOptions('   ', conf), '$mango %command%');
    });

    test('options without %command% follow it, preserved', () {
      expect(
        mangoOptions('-novid -windowed', conf),
        '$mango %command% -novid -windowed',
      );
    });

    test('options with %command% get the env in front', () {
      expect(
        mangoOptions('FOO=1 gamemoderun %command% -x', conf),
        '$mango FOO=1 gamemoderun %command% -x',
      );
    });

    test('already ours: unchanged (null)', () {
      expect(mangoOptions('$mango %command%', conf), isNull);
      expect(mangoOptions('FOO=1 $mango %command% -x', conf), isNull);
    });

    test("kuhy's own MangoHud use is left alone (null)", () {
      expect(mangoOptions('mangohud %command%', conf), isNull);
      expect(mangoOptions('MANGOHUD=1 %command%', conf), isNull);
      expect(mangoOptions('MANGOHUD_CONFIGFILE=/x %command%', conf), isNull);
    });

    test('a path with spaces is single-quoted', () {
      expect(
        mangoOptions('', '/a b/m.conf'),
        "MANGOHUD=1 MANGOHUD_CONFIGFILE='/a b/m.conf' %command%",
      );
    });
  });

  test('addMangoHud: end to end and idempotent', () {
    final once = addMangoHud(vdf(withOptions), 4197610, conf);
    expect(once.result, 'added');
    expect(launchOption(once.text, 4197610), '$mango %command% -novid');
    final twice = addMangoHud(once.text, 4197610, conf);
    expect(twice.result, 'present');
    expect(twice.text, once.text);
  });

  test('addMangoHud: missing key and missing app', () {
    final a = addMangoHud(vdf(''), 3, conf);
    expect(a.result, 'added');
    expect(launchOption(a.text, 3), '$mango %command%');
    final b = addMangoHud(
      vdf(withOptions.replaceAll('"LaunchOptions"', '"Other"')),
      4197610,
      conf,
    );
    expect(launchOption(b.text, 4197610), '$mango %command%');
  });

  test("addMangoHud: kuhy's own mangohud is reported, text untouched", () {
    final text = vdf(withOptions.replaceFirst('-novid', 'mangohud %command%'));
    final r = addMangoHud(text, 4197610, conf);
    expect(r.result, 'user mangohud');
    expect(r.text, text);
  });
}
