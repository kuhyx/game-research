import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/session_services.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory root;
  late FakeSys fake;
  late Directory session;

  setUp(() {
    root = tempDir();
    fake = FakeSys();
    session = Directory(p.join(root.path, 'session'))..createSync();
  });

  group('HotkeyService', () {
    HotkeyService service([Map<String, String> extra = const {}]) =>
        HotkeyService(testConfig(root, extra: extra), fake.sys);

    test('the unit name is per port', () {
      expect(service().unit, 'game-research-keys-18999');
    });

    test('writes the config, clears a stale unit, starts sxhkd', () async {
      await service().start(session.path);
      final rc = File(p.join(session.path, 'sxhkdrc')).readAsStringSync();
      expect(rc, contains("'http://127.0.0.1:18999/api/stop?src=key'"));
      expect(
        fake.calls.first.line,
        'systemctl --user stop game-research-keys-18999.service',
      );
      final run = fake.calls.last;
      expect(run.exe, 'systemd-run');
      expect(run.args, contains('--setenv=DISPLAY=:99'));
      expect(run.args, containsAllInOrder(['sxhkd', '-c']));
      expect(run.args.last, p.join(session.path, 'sxhkdrc'));
    });

    test('an i3 config without our chords is fine', () async {
      final i3 = File(p.join(root.path, 'i3'))
        ..writeAsStringSync('bindsym Mod4+d exec dmenu_run\n');
      await service({'GAME_RESEARCH_I3_CONFIG': i3.path}).start(session.path);
      expect(fake.of('systemd-run'), hasLength(1));
    });

    test('an i3 chord collision refuses to start anything', () async {
      final i3 = File(p.join(root.path, 'i3'))
        ..writeAsStringSync('set \$mod Mod4\nbindsym \$mod+F1 exec x\n');
      await expectLater(
        service({'GAME_RESEARCH_I3_CONFIG': i3.path}).start(session.path),
        throwsA(
          isA<StartError>().having(
            (e) => e.message,
            'message',
            'i3 already binds super + F1',
          ),
        ),
      );
      expect(fake.calls, isEmpty);
      expect(File(p.join(session.path, 'sxhkdrc')).existsSync(), isFalse);
    });

    test('a failing sxhkd start is a StartError', () async {
      fake.onRun = (c) => c.exe == 'systemd-run' ? bad('no bus') : ok();
      await expectLater(
        service().start(session.path),
        throwsA(
          isA<StartError>().having(
            (e) => e.message,
            'message',
            'sxhkd did not start: no bus',
          ),
        ),
      );
    });

    test('stop is one systemctl call', () async {
      await service().stop();
      expect(fake.calls.single.exe, 'systemctl');
    });
  });
}
