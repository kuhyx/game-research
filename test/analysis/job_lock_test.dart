import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/job_lock.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory data;
  late Directory proc;

  setUp(() {
    final root = tempDir();
    data = Directory(p.join(root.path, 'data'))..createSync();
    proc = Directory(p.join(root.path, 'proc'))..createSync();
  });

  /// A /proc entry: `stat` with [comm] and the start time in field 22.
  void alive(int pid, String start, {String comm = '(dart)'}) {
    File(p.join(proc.path, '$pid', 'stat'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '$pid $comm S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 '
        '$start 99 0\n',
      );
  }

  JobLock lock({int self = 100}) =>
      JobLock(data.path, procRoot: proc.path, selfPid: self);

  test('the first job takes the lock, a second is refused and told who', () {
    alive(100, '5000');
    alive(200, '6000');
    expect(lock().acquire('job-a'), isTrue);
    final other = lock(self: 200);
    expect(other.acquire('job-b'), isFalse);
    final holder = other.holder();
    expect(holder?.job, 'job-a');
    expect(holder?.pid, 100);
  });

  test('release frees it, twice is harmless', () {
    alive(100, '5000');
    final l = lock();
    expect(l.acquire('a'), isTrue);
    l
      ..release()
      ..release();
    expect(l.holder(), isNull);
    expect(lock().acquire('b'), isTrue);
  });

  test('a dead owner is taken over', () {
    alive(100, '5000');
    expect(lock().acquire('a'), isTrue);
    Directory(p.join(proc.path, '100')).deleteSync(recursive: true);
    alive(200, '6000');
    final next = lock(self: 200);
    expect(next.holder(), isNull);
    expect(next.acquire('b'), isTrue);
    expect(next.holder()?.job, 'b');
  });

  test('a reused pid with another start time is not the owner', () {
    alive(100, '5000');
    expect(lock().acquire('a'), isTrue);
    alive(100, '9999');
    alive(200, '6000');
    expect(lock(self: 200).acquire('b'), isTrue);
  });

  test('a comm with spaces and parens still yields the start time', () {
    alive(100, '5000', comm: '(a b) c)');
    expect(lock().acquire('a'), isTrue);
    alive(200, '6000');
    expect(lock(self: 200).acquire('b'), isFalse);
  });

  test('a job id may hold colons', () {
    alive(100, '5000');
    expect(lock().acquire('finish:some-game'), isTrue);
    expect(lock().holder()?.job, 'finish:some-game');
  });

  test('a session lock file of an old job counts while its pid lives', () {
    alive(300, '7000');
    File(p.join(proc.path, '300', 'cmdline')).writeAsStringSync(
      '/x/build/analyze/bundle/bin/game_research_analyze\u0000/d/s\u0000',
    );
    final session = Directory(
      p.join(data.path, '20261112-090025-g', 'analysis'),
    )..createSync(recursive: true);
    final file = File(p.join(session.path, 'lock'))..writeAsStringSync('300');
    final l = lock();
    expect(l.holder()?.job, '20261112-090025-g');
    expect(l.acquire('x'), isFalse);
    Directory(p.join(proc.path, '300')).deleteSync(recursive: true);
    expect(l.holder(), isNull, reason: 'dead pid');
    file.writeAsStringSync('junk');
    expect(l.holder(), isNull, reason: 'garbled');
    alive(400, '8000');
    file.writeAsStringSync('400');
    expect(l.holder(), isNull, reason: 'a live pid of another program');
    expect(l.acquire('x'), isTrue);
  });

  test('a garbled global lock is replaced', () {
    Link(p.join(data.path, 'analysis.lock')).createSync('nonsense');
    alive(100, '5000');
    expect(lock().acquire('a'), isTrue);
  });

  test('an owner without a /proc entry has no start time and no life', () {
    final l = lock(self: 424242);
    expect(l.acquire('a'), isTrue);
    expect(l.holder(), isNull);
  });
}
