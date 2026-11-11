import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/game_watcher.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory proc;
  late GameWatcher watcher;

  void process(String pid, String cmdline) {
    Directory(p.join(proc.path, pid)).createSync();
    File(p.join(proc.path, pid, 'cmdline')).writeAsStringSync(cmdline);
  }

  setUp(() {
    proc = tempDir();
    watcher = GameWatcher(
      procRoot: proc.path,
      every: const Duration(milliseconds: 10),
    );
  });
  tearDown(() => watcher.cancel());

  test('running finds the AppId token among numeric pids only', () {
    process('100', 'bash\x00-c\x00ls');
    expect(watcher.running(42), isFalse);
    Directory(p.join(proc.path, 'self')).createSync();
    process('101', 'reaper\x00SteamLaunch\x00AppId=42\x00--\x00game');
    expect(watcher.running(42), isTrue);
    expect(watcher.running(43), isFalse);
  });

  test('a pid without a readable cmdline is skipped', () {
    Directory(p.join(proc.path, '55')).createSync();
    expect(watcher.running(1), isFalse);
  });

  test('a missing proc root runs nothing', () {
    expect(GameWatcher(procRoot: '${proc.path}/none').running(1), isFalse);
  });

  test('the default watcher polls the real /proc every second', () {
    final real = GameWatcher();
    expect(real.procRoot, '/proc');
    expect(real.every, const Duration(seconds: 1));
  });

  test('onExit fires once, after the game was seen and then is gone', () async {
    var exits = 0;
    watcher.watch(42, () => exits++);
    await settle();
    expect(watcher.seen, isFalse);
    expect(exits, 0, reason: 'never seen: keep recording');

    process('7', 'reaper\x00AppId=42\x00');
    await settle();
    expect(watcher.seen, isTrue);
    expect(exits, 0);

    Directory(p.join(proc.path, '7')).deleteSync(recursive: true);
    await settle();
    expect(exits, 1);
    await settle();
    expect(exits, 1);
  });

  test('cancel stops the poll and watch restarts cleanly', () async {
    process('7', 'reaper\x00AppId=42\x00');
    var exits = 0;
    watcher.watch(42, () => exits++);
    await settle();
    watcher
      ..cancel()
      ..cancel();
    Directory(p.join(proc.path, '7')).deleteSync(recursive: true);
    await settle();
    expect(exits, 0);
    watcher.watch(42, () => exits++);
    expect(watcher.seen, isFalse);
  });

  test('a failing /proc listing skips the tick instead of crashing', () async {
    // 2026-11-11: Wine's helpers exiting made listSync throw inside the
    // timer and killed the wrapper mid-session.
    var fail = false;
    List<FileSystemEntity> list(Directory d) => fail
        ? throw const PathNotFoundException('/proc/1', OSError())
        : d.listSync();
    final w = GameWatcher(
      procRoot: proc.path,
      every: const Duration(milliseconds: 10),
      list: list,
    );
    addTearDown(w.cancel);
    var exited = 0;
    process('101', 'reaper\x00AppId=42');
    w.watch(42, () => exited++);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    fail = true;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(exited, 0, reason: 'an unreadable /proc is not a game exit');
    fail = false;
    Directory(p.join(proc.path, '101')).deleteSync(recursive: true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(exited, 1);
  });
}
