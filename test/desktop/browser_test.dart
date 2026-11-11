import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/browser.dart';

import '../support/fakes.dart';

void main() {
  test('profileDir is fixed under the home share', () {
    expect(profileDir('/h'), '/h/.local/share/game-research/profile');
  });

  group('findBrowser', () {
    test('the override wins when it exists', () {
      expect(
        findBrowser(override: '/mine', exists: (f) => f == '/mine'),
        '/mine',
      );
    });

    test('the real chromium binary comes before the launcher', () {
      expect(
        findBrowser(
          override: '',
          exists: (f) =>
              f == '/usr/lib/chromium/chromium' || f == '/usr/bin/chromium',
        ),
        '/usr/lib/chromium/chromium',
      );
    });

    test('falls through the list, then gives up', () {
      expect(
        findBrowser(override: '', exists: (f) => f.endsWith('/chrome')),
        '/opt/google/chrome/chrome',
      );
      expect(findBrowser(override: '', exists: (_) => false), '');
    });

    test('defaults read the environment and the real disk', () {
      final env = Platform.environment['GAME_RESEARCH_BROWSER'] ?? '';
      expect(findBrowser(exists: (f) => f == env && env.isNotEmpty), env);
      expect(findBrowser(), isA<String>());
    });
  });

  test('scaleFlag prints whole numbers without .0', () {
    expect(scaleFlag(2), '--force-device-scale-factor=2');
    expect(scaleFlag(1.25), '--force-device-scale-factor=1.25');
  });

  group('detectScale', () {
    const query = '''
Screen 0: minimum 8 x 8, current 6400 x 2160, maximum 32767 x 32767
DP-2 connected 3840x2160+0+0 (normal left inverted) 597mm x 336mm
   3840x2160     60.00*+
HDMI-0 connected primary 2560x1440+3840+0 (normal left) 597mm x 336mm
''';
    const primaryOnly = '''
DP-2 connected 3840x2160+0+0 (normal) 597mm x 336mm
HDMI-1 connected primary 1920x1080+3840+0 (normal) 597mm x 336mm
''';

    test('a sane override is used without asking xrandr', () async {
      final fake = FakeSys();
      expect(await detectScale(fake.sys, override: '1.5'), 1.5);
      expect(fake.calls, isEmpty);
    });

    test('an insane override is ignored', () async {
      final fake = FakeSys()..onRun = (_) => bad();
      expect(await detectScale(fake.sys, override: '9'), 1);
      expect(await detectScale(fake.sys, override: '0'), 1);
      expect(await detectScale(fake.sys, override: 'x'), 1);
    });

    test('the window output decides, else the primary, else 1', () async {
      final fake = FakeSys()..onRun = (_) => ok(query);
      expect(await detectScale(fake.sys), 1.25);
      expect(await detectScale(fake.sys, windowOutput: 'DP-2'), 2);
      fake.onRun = (_) => ok(primaryOnly);
      expect(await detectScale(fake.sys), 1);
      fake.onRun = (_) => ok('no outputs');
      expect(await detectScale(fake.sys), 1);
    });
  });

  test('browserArgs open the app window with a fixed profile', () {
    final args = browserArgs('/h', port: 8805, scale: 2);
    expect(args.first, '--app=http://127.0.0.1:8805');
    expect(args, contains('--force-device-scale-factor=2'));
    expect(args, contains('--user-data-dir=${profileDir('/h')}'));
    expect(args, contains('--class=$kWindowClass'));
    expect(args, contains('--disable-extensions'));
    expect(
      browserArgs('/h', port: 1),
      contains('--force-device-scale-factor=1'),
    );
  });
}
