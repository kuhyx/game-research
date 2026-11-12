import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/share_harness.dart';

const String _id = ShareHarness.id;
const _copy = '/api/games/4197610/notes/1/copy';

void main() {
  late ShareHarness x;

  setUp(() async => x = (await ShareHarness.start())..clearNote2());

  List<Map<String, Object?>> lines() => [
    for (final l in File(
      p.join(x.session.path, 'markers.jsonl'),
    ).readAsLinesSync())
      jsonDecode(l) as Map<String, Object?>,
  ];

  group('copy needs a note on every marker', () {
    test('part files and part text are 409, nothing is copied', () async {
      x.cutStills();
      expect((await x.post('$_copy?what=files')).status, 409);
      expect((await x.post('$_copy?what=text')).status, 409);
      expect(x.starts, isEmpty);
      expect(x.captions, isEmpty);
    });

    test('one marker without a note is 409, with one it copies', () async {
      x.cutStills();
      expect((await x.post('/api/sessions/$_id/markers/2/copy')).status, 409);
      expect((await x.post('/api/sessions/$_id/markers/1/copy')).status, 200);
    });

    test('after the note is saved the copy works', () async {
      x.cutStills();
      expect((await x.postNote(_id, '2', ' now typed ')).status, 200);
      expect((await x.post('$_copy?what=files')).status, 200);
      expect(x.captions.single.last['note'], 'now typed');
    });
  });

  group('POST /api/sessions/<stamp>/markers/<i>/note', () {
    test('writes that line only, in place', () async {
      final before = lines();
      final r = await x.postNote(_id, '2', 'first line\nsecond');
      expect(r.status, 200);
      expect(r.json, {'ok': true});
      final after = lines();
      expect(after[0], before[0]);
      expect(after[1], {...before[1], 'note': 'first line'});
      expect(
        File(p.join(x.session.path, 'markers.jsonl')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(x.session.path, 'markers.jsonl.tmp')).existsSync(),
        isFalse,
      );
    });

    test('400 for an empty note or a body that is not {note}', () async {
      expect((await x.postNote(_id, '2', '  ')).status, 400);
      expect(
        (await x.s.hit('POST', '/api/sessions/$_id/markers/2/note')).status,
        400,
      );
      expect(
        (await x.s.hit(
          'POST',
          '/api/sessions/$_id/markers/2/note',
          body: '{"note": 5}',
        )).status,
        400,
      );
      expect(lines()[1]['note'], '');
    });

    test('404 for an unknown session or marker', () async {
      expect((await x.postNote('nope', '1', 'a')).status, 404);
      expect((await x.postNote(_id, '9', 'a')).status, 404);
      expect((await x.postNote(_id, 'x', 'a')).status, 404);
    });

    test('404 for a session folder without markers', () async {
      File(p.join(x.session.path, 'markers.jsonl')).deleteSync();
      expect((await x.postNote(_id, '1', 'a')).status, 404);
    });

    test('409 while that session records', () async {
      await x.startRecording();
      final id = (x.s.h.controller.state()['session']! as Map)['id']! as String;
      final dir = Directory(p.join(x.s.h.config.dataDir, id));
      File(p.join(dir.path, 'markers.jsonl'))
          .writeAsStringSync('{"wall_unix":1,"offset_s":1,"tag":"good"}\n');
      expect((await x.postNote(id, '1', 'a')).status, 409);
      // Another session stays editable.
      expect((await x.postNote(_id, '2', 'a')).status, 200);
    });
  });
}
