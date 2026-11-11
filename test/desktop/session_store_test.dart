import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/desktop/session_store.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory root;
  late SessionStore store;
  late String data;

  Directory session(String id, {Map<String, Object?>? meta}) {
    final dir = Directory(p.join(data, id))..createSync(recursive: true);
    if (meta != null) store.writeMeta(dir, meta);
    return dir;
  }

  setUp(() {
    root = tempDir();
    final config = testConfig(root);
    store = SessionStore(config);
    data = config.dataDir;
  });

  group('dir', () {
    test('only plain names of existing folders', () {
      session('2026-a');
      expect(store.dir('2026-a')?.path, p.join(data, '2026-a'));
      expect(store.dir(''), isNull);
      expect(store.dir('../x'), isNull);
      expect(store.dir('a/b'), isNull);
      expect(store.dir('.hidden'), isNull);
      expect(store.dir('missing'), isNull);
    });
  });

  group('meta and status', () {
    test('meta round-trips and survives garbage', () {
      final dir = session('s');
      expect(store.meta(dir), isEmpty);
      store.writeMeta(dir, {'a': 1});
      expect(store.meta(dir), {'a': 1});
      File(p.join(dir.path, 'session.json')).writeAsStringSync('{nope');
      expect(store.meta(dir), isEmpty);
      File(p.join(dir.path, 'session.json')).writeAsStringSync('[1]');
      expect(store.meta(dir), isEmpty);
    });

    test('status reads analysis/status.json, idle without', () {
      final dir = session('s');
      expect(store.status(dir).state, StageState.idle);
      Directory(p.join(dir.path, 'analysis')).createSync();
      File(p.join(dir.path, 'analysis', 'status.json')).writeAsStringSync(
        jsonEncode({'stage': 2, 'done': 1, 'total': 4, 'state': 'running'}),
      );
      expect(store.status(dir).stage, 2);
    });
  });

  group('summary', () {
    test('a bare folder shows zero counts and no draft', () {
      final s = store.summary(session('s', meta: {'appid': 7, 'game': 'G'}));
      expect(s['id'], 's');
      expect(s['appid'], 7);
      expect(s['recording'], isFalse);
      expect(s['markers'], {'good': 0, 'bad': 0, 'confusing': 0, 'note': 0});
      expect(s['draft'], isNull);
    });

    test('markers, recording flag and an existing draft', () {
      final dir = session('s', meta: {'state': 'recording', 'duration_s': 3});
      File(p.join(dir.path, 'markers.jsonl')).writeAsStringSync(
        '${jsonEncode({'wall_unix': 1, 'offset_s': 1, 'tag': 'bad'})}\n',
      );
      final draft = File(p.join(root.path, 'draft.md'))..writeAsStringSync('#');
      Directory(p.join(dir.path, 'analysis')).createSync();
      File(p.join(dir.path, 'analysis', 'stage3.json'))
          .writeAsStringSync(jsonEncode({'draft_en': draft.path}));
      final s = store.summary(dir);
      expect((s['markers']! as Map)['bad'], 1);
      expect(s['recording'], isTrue);
      expect(s['draft'], draft.path);
      expect(s['duration_s'], 3);
    });

    test('a broken markers file or a vanished draft shows nothing', () {
      final dir = session('s', meta: {});
      File(p.join(dir.path, 'markers.jsonl')).writeAsStringSync('not json\n');
      Directory(p.join(dir.path, 'analysis')).createSync();
      File(p.join(dir.path, 'analysis', 'stage3.json'))
          .writeAsStringSync(jsonEncode({'draft_en': '/gone.md'}));
      final s = store.summary(dir);
      expect((s['markers']! as Map)['bad'], 0);
      expect(s['draft'], isNull);
    });
  });

  group('list', () {
    test('no data dir gives an empty list', () {
      expect(store.list(), isEmpty);
    });

    test('newest first; folders without session.json and files skipped', () {
      session('2026-01-a', meta: {'game': 'a'});
      session('2026-03-c', meta: {'game': 'c'});
      session('2026-02-b');
      File(p.join(data, 'settings.json')).writeAsStringSync('{}');
      expect(store.list().map((s) => s['game']), ['c', 'a']);
    });
  });
}
