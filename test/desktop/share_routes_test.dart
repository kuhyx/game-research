import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';
import '../support/server_harness.dart';
import '../support/share_harness.dart';

const String _id = ShareHarness.id;
const _copy = '/api/games/4197610/notes';

void main() {
  late ShareHarness x;

  setUp(() async => x = await ShareHarness.start());

  group('GET notes', () {
    test('slug and parts with the line of each marker', () async {
      final r = await x.s.hit('GET', '/api/games/4197610/notes');
      expect(r.status, 200);
      final body = r.json! as Map<String, Object?>;
      expect(body['slug'], 'librarian');
      final part = (body['parts']! as List).single as Map;
      expect(part['text'], contains('👍 `0:01:05` nice\n👎 `0:01:30`'));
      expect((part['markers'] as List).first, containsPair('still', false));
    });

    test('lazy stills show up on the next read', () async {
      await x.s.hit('GET', '/api/games/4197610/notes');
      await x.s.server.share.notes.idle;
      final r = await x.s.hit('GET', '/api/games/4197610/notes');
      final part = ((r.json! as Map)['parts']! as List).single as Map;
      expect(
        [for (final m in part['markers'] as List) (m as Map)['still']],
        [true, true],
      );
    });

    test('an unknown game is 404', () async {
      expect((await x.s.hit('GET', '/api/games/9/notes')).status, 404);
      expect((await x.s.hit('GET', '/api/games/x/notes')).status, 404);
    });
  });

  group('GET still', () {
    test('the JPEG', () async {
      x.cutStills();
      final r = await x.s.hit('GET', '/api/sessions/$_id/still/2');
      expect([r.status, r.type], [200, 'image/jpeg']);
    });

    test('404 for a missing still, index, session or junk', () async {
      Future<int> get(String tail) async =>
          (await x.s.hit('GET', '/api/sessions/$tail')).status;
      expect(await get('$_id/still/1'), 404);
      x.cutStills();
      expect(await get('$_id/still/3'), 404);
      expect(await get('$_id/still/x'), 404);
      expect(await get('nope/still/1'), 404);
    });
  });

  group('POST copy of a part', () {
    test('files: every still plus the part text', () async {
      x.cutStills();
      final r = await x.post('$_copy/1/copy?what=files');
      expect(r.status, 200);
      const text =
          '**Librarian** · my notes 1/1\n__2026-11-10__\n'
          '👍 `0:01:05` nice\n👎 `0:01:30`';
      expect(r.json, {'ok': true, 'files': 2, 'chars': text.length});
      final dir = p.join(x.s.h.config.dataDir, 'share', 'librarian-1');
      expect(x.starts.single.$1, [
        p.join(dir, '01_good.jpg'),
        p.join(dir, '02_bad.jpg'),
      ]);
      expect(
        utf8.decode(
          File(p.join(dir, '02_bad.jpg')).readAsBytesSync(),
          allowMalformed: true,
        ),
        startsWith('cap|0:01:30||Librarian · 2026-11-10|'),
      );
      expect(x.captions.single.map((j) => j['note']), ['nice', '']);
      expect(
        File(p.join(dir, '..', 'librarian-1.jobs.json')).existsSync(),
        isFalse,
      );
      expect(x.starts.single.$2, text);
    });

    test(
      'a part over two sessions stages unique, line-ordered names',
      () async {
        // Both sessions name their first still m_01_good.jpg.
        final early = x.addEarlierSession(
          '20261109-200000-librarian',
          cut: true,
        );
        x.cutStills();
        final r = await x.post('$_copy/1/copy?what=files');
        expect(r.status, 200);
        final dir = p.join(x.s.h.config.dataDir, 'share', 'librarian-1');
        final names = x.starts.single.$1;
        expect(names, [
          p.join(dir, '01_good.jpg'),
          p.join(dir, '02_good.jpg'),
          p.join(dir, '03_bad.jpg'),
        ]);
        expect(File(names.first).readAsBytesSync().sublist(37), [
          0xFF,
          0xD8,
          9,
        ]);
        expect(x.captions.single.first['right'], 'Librarian · 2026-11-09');
        expect(early.existsSync(), isTrue);
      },
    );

    test('a second copy replaces the staged folder', () async {
      x.cutStills();
      final stale = File(
        p.join(x.s.h.config.dataDir, 'share', 'librarian-1', '09_old.jpg'),
      )..createSync(recursive: true);
      await x.post('$_copy/1/copy?what=files');
      await x.post('$_copy/1/copy?what=files');
      expect(stale.existsSync(), isFalse);
      expect(x.starts, hasLength(2));
    });

    test('text: the text only', () async {
      final r = await x.post('$_copy/1/copy?what=text');
      expect(r.status, 200);
      expect((r.json! as Map)['files'], 0);
      expect(x.starts.single.$1, isEmpty);
    });

    test('files with no stills cut yet is 409', () async {
      expect((await x.post('$_copy/1/copy?what=files')).status, 409);
      expect(x.starts, isEmpty);
    });

    test('files with only some stills cut is 409, nothing copied', () async {
      x.stillOf('m_01_good.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
      final r = await x.post('$_copy/1/copy?what=files');
      expect(r.status, 409);
      expect(x.starts, isEmpty);
      expect(
        Directory(p.join(x.s.h.config.dataDir, 'share')).existsSync(),
        isFalse,
      );
    });

    test('unknown game, part or mode', () async {
      x.cutStills();
      Future<int> status(String path) async => (await x.post(path)).status;
      expect(await status('/api/games/9/notes/1/copy?what=text'), 404);
      expect(await status('$_copy/2/copy?what=text'), 404);
      expect(await status('$_copy/x/copy?what=text'), 404);
      expect(await status('$_copy/1/copy?what=zip'), 400);
      expect(await status('$_copy/1/copy'), 400);
      expect(x.starts, isEmpty);
    });

    test('409 while a session records', () async {
      x.cutStills();
      await x.startRecording();
      expect((await x.post('$_copy/1/copy?what=text')).status, 409);
      expect((await x.post('$_copy/1/copy?what=files')).status, 409);
      expect(x.starts, isEmpty);
      expect(
        Directory(p.join(x.s.h.config.dataDir, 'share')).existsSync(),
        isFalse,
      );
    });

    test('409 without a display, 500 when the helper fails', () async {
      x.helper = (_) => FakeProcess(exit: 3);
      expect((await x.post('$_copy/1/copy?what=text')).status, 409);
      x.helper = (_) => FakeProcess(exit: 1, stderrText: 'boom');
      final failed = await x.post('$_copy/1/copy?what=text');
      expect(failed.status, 500);
      expect(failed.body, contains('boom'));
    });
  });

  group('POST doc copy', () {
    String doc(String name) => p.join(x.s.researchDir, name);
    Future<Reply> copy(String path) =>
        x.post('/api/doc/copy?path=${Uri.encodeQueryComponent(path)}');

    setUp(() {
      File(doc('a.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('long');
    });

    test('the Discord sibling goes out as text only', () async {
      File(doc('a.discord.md')).writeAsStringSync('**short**');
      final r = await copy(doc('a.md'));
      expect(
        [r.status, r.json],
        [
          200,
          {'ok': true, 'files': 0, 'chars': 9},
        ],
      );
      expect(x.starts.single.$1, isEmpty);
      expect(x.starts.single.$2, '**short**');
    });

    test('no sibling is 404, no path 400, outside the docs 403', () async {
      expect((await copy(doc('a.md'))).status, 404);
      expect((await copy(doc('gone.md'))).status, 404);
      expect((await copy('/etc/passwd')).status, 403);
      expect((await x.post('/api/doc/copy')).status, 400);
      expect(x.starts, isEmpty);
    });

    test('409 while a session records, 409 without a display', () async {
      File(doc('a.discord.md')).writeAsStringSync('s');
      x.helper = (_) => FakeProcess(exit: 3);
      expect((await copy(doc('a.md'))).status, 409);
      await x.startRecording();
      expect((await copy(doc('a.md'))).status, 409);
    });
  });
}
