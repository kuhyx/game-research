import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/safe_json.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory dir;
  setUp(() => dir = tempDir());
  File file(String name, String text) =>
      File(p.join(dir.path, name))..writeAsStringSync(text);

  group('parseJsonl', () {
    test('keeps objects, skips and counts everything else', () {
      final r = parseJsonl('{"a":1}\n\n[1]\nnot json\n{"b":2}\n{"c":');
      expect(r.rows, [
        {'a': 1},
        {'b': 2},
      ]);
      expect(r.skipped, 3);
      expect(r.terminated, isFalse);
      expect(r.clean, isFalse);
    });

    test('a clean file is clean', () {
      final r = parseJsonl('{"a":1}\n{"b":2}\n');
      expect([r.rows.length, r.skipped, r.clean], [2, 0, true]);
      expect(parseJsonl('').clean, isTrue);
    });

    test('accept drops rows it rejects or throws on', () {
      final r = parseJsonl(
        '{"a":1}\n{"a":2}\n{"a":3}\n',
        accept: (m) =>
            m['a']! as int == 3 ? throw StateError('x') : m['a'] == 1,
      );
      expect(r.rows, [
        {'a': 1},
      ]);
      expect(r.skipped, 2);
    });
  });

  group('readJsonl', () {
    test('strips NUL bytes, drops the torn tail, reports the damage', () {
      final f = file('c.jsonl', '{"a":1}\n{"b":2}\x00\x00\n{"c":\x00\x00\x00');
      final r = readJsonl(f);
      expect(r.rows, [
        {'a': 1},
        {'b': 2},
      ]);
      expect(r.skipped, 1);
      expect(r.hadNul, isTrue);
      expect(r.clean, isFalse);
    });

    test('NUL bytes alone make the file unclean', () {
      final r = readJsonl(file('c.jsonl', '{"a":1}\n\x00\x00\x00'));
      expect(r.rows, hasLength(1));
      expect(r.skipped, 0);
      expect(r.clean, isFalse);
    });

    test('a missing file and malformed UTF-8 read without throwing', () {
      expect(readJsonl(File(p.join(dir.path, 'none'))).rows, isEmpty);
      final f = File(p.join(dir.path, 'u.jsonl'))
        ..writeAsBytesSync([...'{"a":1}\n'.codeUnits, 0xE2, 0x82]);
      expect(readJsonl(f).rows, hasLength(1));
    });
  });

  group('whole-file JSON', () {
    test('readJsonObject is null for missing, corrupt and non-objects', () {
      expect(readJsonObject(File(p.join(dir.path, 'none'))), isNull);
      expect(readJsonObject(file('a.json', '{"a":')), isNull);
      expect(readJsonObject(file('b.json', '[1]')), isNull);
      expect(readJsonObject(file('c.json', '\x00\x00\x00')), isNull);
      expect(readJsonObject(file('d.json', '{"a":1}\x00\x00')), {'a': 1});
      expect(readJson(file('e.json', '[1,2]')), [1, 2]);
    });

    test('writeAtomic goes through a tmp file and leaves none', () {
      final f = File(p.join(dir.path, 'sub', 's.json'));
      writeAtomic(f, '{"v":1}');
      writeAtomic(f, '{"v":2}');
      expect(f.readAsStringSync(), '{"v":2}');
      expect(File('${f.path}.tmp').existsSync(), isFalse);
    });

    test('a stale tmp from a cut write never reaches the real file', () {
      final f = file('s.json', '{"v":1}');
      file('s.json.tmp', '{"v":');
      expect(readJsonObject(f), {'v': 1});
      writeAtomic(f, '{"v":2}');
      expect(readJsonObject(f), {'v': 2});
    });

    test('writeJsonlAtomic writes one line per row', () {
      final f = File(p.join(dir.path, 'r.jsonl'));
      writeJsonlAtomic(f, [
        {'a': 1},
        {'b': 2},
      ]);
      expect(f.readAsStringSync(), '{"a":1}\n{"b":2}\n');
    });
  });
}
