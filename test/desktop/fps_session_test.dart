import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/fps_session.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

/// The fake clock; the fixture log spans [t - 1.0, t + 0.05].
const t = 1000000.0;

void main() {
  late Directory root;
  late Config config;
  late FpsSession fps;
  late FakeSys fake;

  List<Map<String, Object?>> events(String name) => [
    for (final l in EventLog(config.logFile).tail(1000))
      if ((jsonDecode(l) as Map<String, Object?>)['event'] == name)
        jsonDecode(l) as Map<String, Object?>,
  ];

  setUp(() {
    root = tempDir();
    fake = FakeSys(now: t, step: 0);
    config = testConfig(
      root,
      extra: {
        'GAME_RESEARCH_REPO': Directory.current.path,
        'GAME_RESEARCH_PROC': p.join(root.path, 'proc'),
        'GAME_RESEARCH_STEAM_PID': p.join(root.path, 'steam.pid'),
      },
    );
    Directory(config.procRoot).createSync();
    fps = FpsSession(config, fake.sys, EventLog(config.logFile));
  });

  group('collect', () {
    final fixture = File('test/fixtures/mangohud_0.8.csv');
    late Directory session;

    File spool(String name, {required double endUnix, String? text}) {
      return File(p.join(fps.spoolDir, name))
        ..createSync(recursive: true)
        ..writeAsStringSync(text ?? fixture.readAsStringSync())
        ..setLastModifiedSync(
          DateTime.fromMillisecondsSinceEpoch((endUnix * 1000).round()),
        );
    }

    setUp(() {
      session = Directory(p.join(root.path, 'data', 's1'))
        ..createSync(recursive: true);
    });

    test('moves overlapping logs into fps/, returns the stats', () {
      spool('Librarian.exe_2026.csv', endUnix: t + 0.05);
      spool('before.csv', endUnix: t - 400000);
      final s = fps.collect(session, from: t - 0.505, to: t + 100)!;
      expect(s, {'avg': 91.1, 'p1_low': 20.0, 'min': 20.0, 'samples': 51});
      expect(
        File(p.join(session.path, 'fps', 'Librarian.exe_2026.csv'))
            .existsSync(),
        true,
      );
      expect(
        File(p.join(fps.spoolDir, 'Librarian.exe_2026.csv')).existsSync(),
        false,
      );
      expect(File(p.join(fps.spoolDir, 'before.csv')).existsSync(), true);
      final e = events('fps').single;
      expect(e['avg'], s['avg']);
      expect(e['files'], ['Librarian.exe_2026.csv']);
    });

    test('stats cover only the session window', () {
      spool('g.csv', endUnix: t + 0.05);
      final s = fps.collect(session, from: t - 0.505, to: t + 100)!;
      expect(s['samples'], 51);
      expect(s['min'], 20.0);
    });

    test('the log with the most samples in the window is the game', () {
      spool('Game.exe_1.csv', endUnix: t + 0.05);
      spool(
        'Other_1.csv',
        endUnix: t + 0.05,
        text: 'fps,frametime,elapsed\n100,10,10000000\n',
      );
      final s = fps.collect(session, from: 0, to: 9000000000)!;
      expect(s['samples'], 100);
      expect(Directory(p.join(session.path, 'fps')).listSync().length, 2);
    });

    test('no spool folder or no overlap: null, event says none', () {
      expect(fps.collect(session, from: 0, to: 1), isNull);
      spool('late.csv', endUnix: t + 9000);
      expect(fps.collect(session, from: 0, to: 1), isNull);
      expect(Directory(p.join(session.path, 'fps')).existsSync(), false);
      expect(events('fps').map((e) => e['result']), ['none', 'none']);
    });

    test('an unparsable log is moved but yields no stats', () {
      spool('junk.csv', endUnix: t, text: 'nothing useful\n');
      expect(fps.collect(session, from: 0, to: 9000000000), isNull);
      expect(File(p.join(session.path, 'fps', 'junk.csv')).existsSync(), true);
    });

    test('prunes spool files older than 7 days, keeps the rest', () {
      final now = fake.now;
      spool('old.csv', endUnix: now - 8 * 86400);
      spool('young.csv', endUnix: now - 6 * 86400);
      File(p.join(fps.spoolDir, 'notes.txt'))
        ..writeAsStringSync('x')
        ..setLastModifiedSync(DateTime.fromMillisecondsSinceEpoch(1000));
      fps.collect(session, from: now, to: now + 1);
      expect(File(p.join(fps.spoolDir, 'old.csv')).existsSync(), false);
      expect(File(p.join(fps.spoolDir, 'young.csv')).existsSync(), true);
      expect(File(p.join(fps.spoolDir, 'notes.txt')).existsSync(), true);
    });
  });
}
