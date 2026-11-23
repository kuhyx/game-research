import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/steam_vdf.dart';

const conf = '/home/k/data/game-research/mangohud.conf';
const mango = 'MANGOHUD=1 MANGOHUD_CONFIGFILE=$conf';

/// A one-app `localconfig.vdf` whose launch options are [options].
String vdf(String options) =>
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
\t\t\t\t\t"7"
\t\t\t\t\t{
\t\t\t\t\t\t"LaunchOptions"\t\t"$options"
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}
\t\t}
\t}
}
''';

void main() {
  group('addMangoHud: our option with another config path', () {
    for (final old in [
      '/s/claude-scratch/playstudy/display-149/mangohud.conf',
      "'/a b/mangohud.conf'",
    ]) {
      test('$old is rewritten to the current path', () {
        final r = addMangoHud(
          vdf('MANGOHUD=1 MANGOHUD_CONFIGFILE=$old %command% -x'),
          7,
          conf,
        );
        expect(r.result, 'updated');
        expect(launchOption(r.text, 7), '$mango %command% -x');
        expect(addMangoHud(r.text, 7, conf).result, 'present');
      });
    }

    test('a quoted current path is ours: present', () {
      const quoted = "MANGOHUD=1 MANGOHUD_CONFIGFILE='$conf' %command%";
      final text = vdf(quoted);
      expect(addMangoHud(text, 7, conf), (text: text, result: 'present'));
    });

    for (final own in [
      'MANGOHUD=1 MANGOHUD_CONFIGFILE=/h/MangoHud/MangoHud.conf %command%',
      'MANGOHUD=1 MANGOHUD_CONFIGFILE=/h/other.conf %command%',
      'FOO=1 MANGOHUD=1 MANGOHUD_CONFIGFILE=/s/mangohud.conf %command%',
      'mangohud %command%',
    ]) {
      test("kuhy's own option '$own' is left alone", () {
        final text = vdf(own);
        expect(addMangoHud(text, 7, conf), (
          text: text,
          result: 'user mangohud',
        ));
      });
    }
  });
}
