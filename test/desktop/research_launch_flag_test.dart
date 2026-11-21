import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/recorder.dart';
import 'package:game_research/desktop/session_flow.dart';
import 'package:game_research/desktop/steam_library.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';
import '../support/session_harness.dart';

const librarian = 4197610;

/// The launch flag tells the enforcer a research game is being started
/// through PlayStudy: up before Steam is asked, down once recording (the
/// recording flag takes over), on cancel and when the wait gives up.
void main() {
  late Harness h;
  late SessionFlow flow;

  File flag() => File(p.join(h.config.dataDir, 'research_launch.pid'));

  setUp(() {
    h = Harness(extra: {'GAME_RESEARCH_WINDOW_TIMEOUT_S': '0.3'});
    final apps = Directory(p.join(h.config.steamRoot, 'steamapps'))
      ..createSync(recursive: true);
    File('test/fixtures/appmanifest_$librarian.acf')
        .copySync(p.join(apps.path, 'appmanifest_$librarian.acf'));
    flow = SessionFlow(
      h.controller,
      SteamLibrary(h.config.steamRoot),
      every: const Duration(milliseconds: 10),
    );
  });
  tearDown(() => flow.cancel('test'));

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await settle();
    }
  }

  test('up before the launch, down once recording', () async {
    final harnessRun = h.fake.onRun!;
    var sawFlag = false;
    h.fake.onRun = (c) {
      if (c.exe == 'systemd-run') sawFlag = flag().existsSync();
      return harnessRun(c);
    };
    await flow.start(librarian);
    expect(sawFlag, isTrue);
    expect(flag().readAsStringSync(), '$pid');
    h.gameRuns(librarian);
    await until(() => h.controller.recording);
    expect(flag().existsSync(), isFalse);
    expect(
      File(p.join(h.config.dataDir, 'recording.pid')).existsSync(),
      isTrue,
    );
    await settle();
    h.gameExits();
    await h.untilStopped();
  });

  test('down on cancel', () async {
    await flow.start(librarian);
    expect(flow.cancel('esc'), isTrue);
    expect(flag().existsSync(), isFalse);
  });

  test('down when the window never appears', () async {
    await flow.start(librarian);
    await until(() => flow.error.isNotEmpty);
    expect(flag().existsSync(), isFalse);
  });

  test('down when the launch fails', () async {
    h.failRuns.add('systemd-run');
    await expectLater(flow.start(librarian), throwsA(isA<StartError>()));
    expect(flag().existsSync(), isFalse);
  });
}
