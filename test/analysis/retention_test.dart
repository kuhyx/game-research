import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/resume.dart';
import 'package:game_research/analysis/retention.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

// kuhy, 2026-11-12: recordings are big; the .mkv goes 14 days after the
// game's research is finished, the rest of the session stays.
void main() {
  late Fixture fx;
  late String data;
  const day = 86400.0;
  const finishedAt = 1700000000.0;

  void finish({String state = 'done', double? at = finishedAt}) {
    File(p.join(data, 'games', 'alpha', 'finish.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'state': state,
          'sessions': ['20261112-090025'],
          'finished_unix': ?at,
        }),
      );
  }

  File video() => File(p.join(fx.session.path, 'recording.mkv'));

  setUp(() {
    fx = Fixture();
    data = p.join(fx.root.path, 'data');
    fx.out('status.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'state': 'done'}));
    File(p.join(fx.session.path, 'recording.ts')).writeAsStringSync('ts');
  });

  List<String> run(double now) => applyRetention(testConfig(fx.root), now);

  test('14 days after finish the recording goes, the rest stays', () {
    finish();
    expect(run(finishedAt + 13.9 * day), isEmpty);
    expect(video().existsSync(), isTrue);
    expect(run(finishedAt + 14 * day), [video().path]);
    expect(video().existsSync(), isFalse);
    expect(File(p.join(fx.session.path, 'recording.ts')).existsSync(), isTrue);
    expect(fx.out('status.json').existsSync(), isTrue);
    expect(run(finishedAt + 30 * day), isEmpty, reason: 'nothing left');
  });

  test('no finish.json, an unfinished one, or no timestamp: kept', () {
    expect(run(finishedAt + 99 * day), isEmpty);
    finish(state: 'running');
    expect(run(finishedAt + 99 * day), isEmpty);
    finish(at: null);
    expect(run(finishedAt + 99 * day), isEmpty);
    File(p.join(data, 'games', 'alpha', 'finish.json')).writeAsStringSync('{');
    expect(run(finishedAt + 99 * day), isEmpty);
    expect(video().existsSync(), isTrue);
  });

  test('only sessions that were merged and are analysed lose theirs', () {
    finish();
    // A later session the finish did not merge.
    final later = Directory(p.join(data, '20261201-100000-alpha'))
      ..createSync();
    File(p.join(later.path, 'session.json'))
        .writeAsStringSync(jsonEncode(fx.meta));
    File(p.join(later.path, 'recording.mkv')).writeAsStringSync('v');
    // Another game, same stamp scheme.
    final other = Directory(p.join(data, '20261112-090025-beta'))..createSync();
    File(p.join(other.path, 'session.json'))
        .writeAsStringSync(jsonEncode({...fx.meta, 'slug': 'beta'}));
    File(p.join(other.path, 'recording.mkv')).writeAsStringSync('v');
    run(finishedAt + 20 * day);
    expect(video().existsSync(), isFalse);
    expect(File(p.join(later.path, 'recording.mkv')).existsSync(), isTrue);
    expect(File(p.join(other.path, 'recording.mkv')).existsSync(), isTrue);
  });

  test('a session whose analysis is not done keeps its recording', () {
    finish();
    fx.out('status.json').writeAsStringSync(jsonEncode({'state': 'failed'}));
    expect(run(finishedAt + 20 * day), isEmpty);
    fx.out('status.json').deleteSync();
    expect(run(finishedAt + 20 * day), isEmpty);
    expect(video().existsSync(), isTrue);
  });

  test('--resume-all applies it', () async {
    finish();
    final fake = FakeSys(now: finishedAt + 15 * day);
    await ResumeAll(
      testConfig(fx.root),
      fake.sys,
      MockClient((_) async => throw StateError('no network')),
    ).run();
    expect(video().existsSync(), isFalse);
  });
}
