import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';
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
      expect(x.starts.single.$1, [
        p.join(x.session.path, 'analysis', 'clips', 'm_01_good.jpg'),
        p.join(x.session.path, 'analysis', 'clips', 'm_02_bad.jpg'),
      ]);
      expect(x.starts.single.$2, text);
    });

    test('text: the text only', () async {
      final r = await x.post('$_copy/1/copy?what=text');
      expect(r.status, 200);
      expect((r.json! as Map)['files'], 0);
      expect(x.starts.single.$1, isEmpty);
    });

    test('files with no stills cut yet is 404', () async {
      expect((await x.post('$_copy/1/copy?what=files')).status, 404);
      expect(x.starts, isEmpty);
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
      expect(x.starts, isEmpty);
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
}
