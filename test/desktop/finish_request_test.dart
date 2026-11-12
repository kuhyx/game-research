import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/server_harness.dart';

void main() {
  late ServerHarness s;

  Future<File> doc(String rel, [String text = '# hi']) async {
    final f = File(p.join(s.researchDir, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    return f;
  }

  group('finish', () {
    setUp(() async {
      s = await ServerHarness.start(
        games: {4197610: 'Librarian: Tidy Up the Arcane Library!'},
      );
    });

    void session(String id, {String? draft}) {
      final dir = Directory(p.join(s.h.config.dataDir, id))
        ..createSync(recursive: true);
      s.h.parts.store.writeMeta(dir, {'appid': 4197610});
      if (draft != null) {
        Directory(p.join(dir.path, 'analysis')).createSync();
        File(p.join(dir.path, 'analysis', 'stage3.json'))
            .writeAsStringSync(jsonEncode({'draft': draft}));
      }
    }

    const slug = 'librarian-tidy-up-the-arcane-library';
    File finishFile() =>
        File(p.join(s.h.config.dataDir, 'games', slug, 'finish.json'));
    Map<String, Object?> finishJson() =>
        jsonDecode(finishFile().readAsStringSync()) as Map<String, Object?>;

    test('refuses only an unknown game', () async {
      expect((await s.hit('POST', '/api/games/9/finish')).status, 404);
      expect((await s.hit('POST', '/api/games/x/finish')).status, 404);
    });

    test('no drafts yet: recorded as queued and launched anyway', () async {
      session('20261112-a');
      final r = await s.hit('POST', '/api/games/4197610/finish');
      expect(r.status, 202);
      expect(r.json, containsPair('queued', true));
      expect(finishJson(), containsPair('state', 'queued'));
      expect(finishJson(), containsPair('appid', 4197610));
      expect(finishJson()['requested_unix'], isA<num>());
      expect(s.h.fake.calls.last.args, ['--finish', slug]);
      final g = ((await s.hit('GET', '/api/games')).json! as List).single;
      expect((g as Map)['finish'], containsPair('state', 'waiting'));
    });

    test('launches the analyzer with --finish <slug> every press', () async {
      final d = await doc('games/x/d.md');
      session('20261112-a', draft: d.path);
      final r = await s.hit('POST', '/api/games/4197610/finish');
      expect(
        [r.status, r.json],
        [
          202,
          {'ok': true, 'slug': slug, 'queued': true, 'started': true},
        ],
      );
      expect(s.h.fake.calls.last.args, ['--finish', slug]);
      s.h.fake.calls.clear();
      expect((await s.hit('POST', '/api/games/4197610/finish')).status, 202);
      expect(s.h.fake.calls.last.args, ['--finish', slug]);
    });

    test('a running job is not launched twice; the request stays', () async {
      File(p.join(s.h.config.dataDir, 'games', slug, 'status.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'state': 'running'}));
      final r = await s.hit('POST', '/api/games/4197610/finish');
      expect([r.status, (r.json! as Map)['started']], [202, false]);
      expect(finishFile().existsSync(), isTrue);
      expect(s.h.fake.calls.where((c) => c.args.contains('--finish')), isEmpty);
    });

    test('a failed launch is still recorded (the timer picks it up)', () async {
      s.h.fake.onStart = (_) => throw const ProcessException('x', []);
      final r = await s.hit('POST', '/api/games/4197610/finish');
      expect([r.status, (r.json! as Map)['started']], [202, false]);
      expect(finishJson(), containsPair('state', 'queued'));
    });

    test(
      'a done finish keeps its report; a failed status is cleared',
      () async {
        finishFile()
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({'state': 'done', 'report': '/r.md'}));
        File(p.join(s.h.config.dataDir, 'games', slug, 'status.json'))
            .writeAsStringSync(jsonEncode({'state': 'failed'}));
        await s.hit('POST', '/api/games/4197610/finish');
        expect(finishJson(), containsPair('state', 'done'));
        expect(finishJson(), containsPair('report', '/r.md'));
        expect(finishJson(), containsPair('appid', 4197610));
        finishFile().deleteSync();
        await s.hit('POST', '/api/games/4197610/finish');
        expect(
          File(p.join(s.h.config.dataDir, 'games', slug, 'status.json'))
              .existsSync(),
          isFalse,
        );
      },
    );

    test('/api/finish maps app id to the state, nothing logged', () async {
      expect((await s.hit('GET', '/api/finish')).json, <String, Object?>{});
      File(p.join(s.h.config.dataDir, 'games', slug, 'status.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'state': 'running', 'progress': 0.3}));
      final m = (await s.hit('GET', '/api/finish')).json! as Map;
      expect(m['4197610'], containsPair('state', 'running'));
      expect(s.h.events, isNot(contains('picker')));
    });

    test('/api/games carries slug and the finish state', () async {
      var g = ((await s.hit('GET', '/api/games')).json! as List).single as Map;
      expect(g['slug'], slug);
      expect(g['finish'], isNull);
      File(p.join(s.h.config.dataDir, 'games', slug, 'finish.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'state': 'done', 'report': '/r.md'}));
      g = ((await s.hit('GET', '/api/games')).json! as List).single as Map;
      expect(g['finish'], containsPair('report', '/r.md'));
      expect(g['finish'], containsPair('state', 'done'));
    });
  });
}
