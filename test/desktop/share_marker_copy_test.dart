import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/share_harness.dart';

const String _id = ShareHarness.id;

void main() {
  late ShareHarness x;

  setUp(() async => x = await ShareHarness.start());

  Future<int> status(String tail) async =>
      (await x.post('/api/sessions/$tail/copy')).status;

  test('copies the line of a marker and its still', () async {
    x.cutStills();
    final r = await x.post('/api/sessions/$_id/markers/1/copy');
    expect(r.json, {
      'ok': true,
      'files': 1,
      'chars': '👍 `0:01:05` nice'.length,
    });
    expect(x.starts.single.$2, '👍 `0:01:05` nice');
    final staged = p.join(
      x.s.h.config.dataDir,
      'share',
      'marker-$_id-1',
      '01_good.jpg',
    );
    expect(x.starts.single.$1, [staged]);
    expect(
      utf8.decode(File(staged).readAsBytesSync(), allowMalformed: true),
      startsWith('cap|0:01:05|nice|Librarian · 2026-11-10|'),
    );
    expect(x.stillOf('m_01_good.jpg').readAsBytesSync(), [
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      7,
    ], reason: 'the original stays untouched');
  });

  test('a failing captioner is 500', () async {
    x
      ..cutStills()
      ..captionExit = 2;
    expect(await status('$_id/markers/1'), 500);
    expect(x.starts, isEmpty);
  });

  test('a failing captioner is 500 and copies nothing', () async {
    x
      ..cutStills()
      ..captionExit = 1;
    expect(
      (await x.post('/api/games/4197610/notes/1/copy?what=files')).status,
      500,
    );
    expect(x.starts, isEmpty);
  });

  test('a captioner that writes nothing is 500', () async {
    x.cutStills();
    x.s.h.fake.onRun = (c) =>
        c.exe == '/usr/bin/python3' ? ProcessResult(1, 0, '', '') : null;
    expect(
      (await x.post('/api/games/4197610/notes/1/copy?what=files')).status,
      500,
    );
  });

  test('a missing captioner is 500', () async {
    x.cutStills();
    x.s.h.fake.onRun = (c) => throw ProcessException(c.exe, c.args, 'gone');
    expect(
      (await x.post('/api/games/4197610/notes/1/copy?what=files')).status,
      500,
    );
  });

  test('404 without a still, session or marker', () async {
    expect(await status('$_id/markers/1'), 404);
    x.cutStills();
    expect(await status('$_id/markers/9'), 404);
    expect(await status('nope/markers/1'), 404);
    expect(await status('$_id/markers/x'), 404);
    expect(x.starts, isEmpty);
  });

  test('409 while a session records', () async {
    x.cutStills();
    await x.startRecording();
    expect(await status('$_id/markers/1'), 409);
    expect(x.starts, isEmpty);
  });
}
