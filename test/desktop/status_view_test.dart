import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/game_store.dart';
import 'package:game_research/desktop/session_store.dart';
import 'package:game_research/desktop/status_view.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  group('statusView', () {
    test('an old status.json (no tokens) still reads', () {
      expect(
        statusView({'stage': 2, 'done': 3, 'total': 6, 'state': 'running'}),
        {
          'stage': 2,
          'done': 3,
          'total': 6,
          'state': 'running',
          'progress': 0.5,
          'tokens': null,
          'cost_usd': null,
          'eta_s': null,
        },
      );
    });

    test('the new fields pass through; waiting and interrupted are kept', () {
      final v = statusView({
        'stage': 3,
        'done': 0,
        'total': 1,
        'state': 'waiting',
        'progress': 0.7,
        'tokens': {'in': 10, 'out': 5, 'cache_read': 1, 'cache_write': 2},
        'cost_usd': 0.25,
        'eta_s': 90,
        'error': 'usage limit',
      });
      expect(v['state'], 'waiting');
      expect(v['progress'], 0.7);
      expect(v['tokens'], containsPair('out', 5));
      expect(v['cost_usd'], 0.25);
      expect(v['eta_s'], 90);
      expect(v['error'], 'usage limit');
      expect(statusView({'state': 'interrupted'})['state'], 'interrupted');
    });

    test('unknown state reads as idle; done is full progress', () {
      expect(statusView({'state': 'weird'})['state'], 'idle');
      expect(statusView({'state': 'done'})['progress'], 1);
      expect(statusView({})['progress'], 0);
    });
  });

  group('session summary', () {
    test('draft (new key or old), fps and analysis extras', () {
      final root = tempDir();
      final config = testConfig(root);
      final store = SessionStore(config);
      final dir = Directory(p.join(config.dataDir, 's'))
        ..createSync(recursive: true);
      store.writeMeta(dir, {
        'appid': 1,
        'fps': {'avg': 59.5, 'p1_low': 40, 'min': 30, 'samples': 900},
      });
      Directory(p.join(dir.path, 'analysis')).createSync();
      File(p.join(dir.path, 'analysis', 'status.json')).writeAsStringSync(
        jsonEncode({
          'stage': 1,
          'done': 1,
          'total': 4,
          'state': 'running',
          'tokens': {'in': 1, 'out': 2},
          'cost_usd': 0.5,
          'eta_s': 60,
        }),
      );
      final draft = File(p.join(root.path, 'd.md'))..writeAsStringSync('#');
      final s3 = File(p.join(dir.path, 'analysis', 'stage3.json'))
        ..writeAsStringSync(jsonEncode({'draft_en': draft.path}));
      var s = store.summary(dir);
      expect(s['draft'], draft.path, reason: 'old key');
      s3.writeAsStringSync(jsonEncode({'draft': draft.path}));
      s = store.summary(dir);
      expect(s['draft'], draft.path);
      expect(s['fps'], containsPair('avg', 59.5));
      final a = s['analysis']! as Map;
      expect(a['cost_usd'], 0.5);
      expect(a['eta_s'], 60);
      expect(a['tokens'], {'in': 1, 'out': 2});
    });
  });

  group('GameStore', () {
    late GameStore games;
    late String dir;
    setUp(() {
      final config = testConfig(tempDir());
      games = GameStore(config);
      dir = p.join(config.dataDir, 'games', 'librarian');
    });

    void put(String name, Map<String, Object?> json, {int ageS = 0}) {
      File(p.join(dir, name))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(json))
        ..setLastModifiedSync(DateTime.now().subtract(Duration(seconds: ageS)));
    }

    test('no files: null', () => expect(games.finish('librarian'), isNull));

    test('status.json while running', () {
      put('status.json', {
        'stage': 1,
        'done': 1,
        'total': 2,
        'state': 'running',
      });
      expect(games.finish('librarian'), containsPair('state', 'running'));
    });

    test('finish.json brings the report and merged paths', () {
      put('status.json', {'state': 'done', 'progress': 1}, ageS: 5);
      put('finish.json', {
        'state': 'done',
        'report': '/r.md',
        'merged': '/m.md',
        'sessions': ['a', 'b'],
        'tokens': {'in': 3},
        'cost_usd': 1.5,
      });
      final f = games.finish('librarian')!;
      expect(f['state'], 'done');
      expect(f['report'], '/r.md');
      expect(f['merged'], '/m.md');
      expect(f['sessions'], ['a', 'b']);
      expect(f['cost_usd'], 1.5);
    });

    test('a newer status.json (a rerun) wins over an older finish.json', () {
      put('finish.json', {'state': 'done', 'report': '/r.md'}, ageS: 60);
      put('status.json', {'state': 'running', 'progress': 0.2});
      final f = games.finish('librarian')!;
      expect(f['state'], 'running');
      expect(f['report'], '/r.md', reason: 'the old report stays openable');
    });

    test('state reads garbage as null', () {
      File(p.join(dir, 'status.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{{');
      expect(games.finish('librarian'), isNull);
    });
  });
}
