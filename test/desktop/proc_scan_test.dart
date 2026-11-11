import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/proc_scan.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory root;
  late ProcScan scan;
  late String pidFile;

  void process(String pid, {String cmdline = '', String? environ}) {
    final dir = Directory(p.join(root.path, 'proc', pid))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'cmdline')).writeAsStringSync(cmdline);
    if (environ != null) {
      File(p.join(dir.path, 'environ')).writeAsStringSync(environ);
    }
  }

  setUp(() {
    root = tempDir();
    scan = ProcScan(p.join(root.path, 'proc'));
    pidFile = p.join(root.path, 'steam.pid');
  });

  test('a missing proc root has no game processes', () {
    expect(scan.gamePids(1), isEmpty);
  });

  test('steamClient: only a live Steam process from the pid file', () {
    expect(scan.steamClient(pidFile), isNull, reason: 'no pid file');
    File(pidFile).writeAsStringSync('x');
    expect(scan.steamClient(pidFile), isNull, reason: 'no number');
    File(pidFile).writeAsStringSync('40\n');
    expect(scan.steamClient(pidFile), isNull, reason: 'stale pid');
    process('40', cmdline: 'bash');
    expect(scan.steamClient(pidFile), isNull, reason: 'pid reused');
    process('40', cmdline: '/home/k/.local/share/Steam/ubuntu12_32/steam');
    expect(scan.steamClient(pidFile), 40);
  });

  test('gamePids: SteamAppId in the environment or AppId in argv', () {
    process('9', environ: 'A=1\x00SteamAppId=7\x00');
    process('3', cmdline: 'reaper\x00SteamLaunch\x00AppId=7\x00--');
    process('5', environ: 'SteamAppId=70\x00');
    process('6', cmdline: 'steam');
    Directory(p.join(root.path, 'proc', 'self')).createSync();
    Directory(p.join(root.path, 'proc', '8')).createSync(); // no files
    expect(scan.gamePids(7), [3, 9]);
  });

  test('a /proc entry vanishing mid-listing is retried, then thrown', () {
    var calls = 0;
    List<FileSystemEntity> flaky(Directory d) {
      if (++calls == 1) throw const PathNotFoundException('/proc/9', OSError());
      return d.listSync();
    }

    process('9', environ: 'SteamAppId=7\x00');
    expect(ProcScan(p.join(root.path, 'proc'), list: flaky).gamePids(7), [9]);
    List<FileSystemEntity> broken(Directory d) =>
        throw const PathNotFoundException('/proc/9', OSError());
    final bad = ProcScan(p.join(root.path, 'proc'), list: broken);
    expect(() => bad.gamePids(7), throwsA(isA<FileSystemException>()));
    expect(bad.running(7), isNull);
    expect(scan.running(7), isTrue);
    expect(scan.running(8), isFalse);
  });
}
