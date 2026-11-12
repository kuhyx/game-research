import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/clip_owner.dart';

import '../support/fakes.dart';

void main() {
  late FakeSys fake;
  late ClipOwner owner;
  late String root;
  // What the helper sees at start: the text file's content.
  final texts = <String>[];

  setUp(() {
    final dir = tempDir();
    root = dir.path;
    fake = FakeSys();
    texts.clear();
    fake.onStart = (c) {
      final i = c.args.indexOf('--text-file');
      if (i >= 0) texts.add(File(c.args[i + 1]).readAsStringSync());
      return FakeProcess(stdoutText: 'ready\n');
    };
    owner = ClipOwner(
      testConfig(dir),
      fake.sys,
      readyTimeout: const Duration(milliseconds: 300),
    );
  });

  test(
    'starts the helper on the private display and waits for ready',
    () async {
      await owner.copy(files: ['/s/a.jpg', '/s/b.jpg'], text: 'hello ✓');
      final call = fake.of('/usr/bin/python3').single;
      expect(call.isStart, isTrue);
      expect(call.args.first, endsWith('helpers/clip_owner.py'));
      expect(call.args.sublist(1, 2), ['--text-file']);
      expect(call.args.sublist(3), ['/s/a.jpg', '/s/b.jpg']);
      expect(call.env, containsPair('DISPLAY', ':99'));
      expect(call.env, containsPair('GAME_RESEARCH_TEST', '1'));
      expect(texts, ['hello ✓']);
    },
  );

  test('the text file is gone once the helper owns the clipboard', () async {
    await owner.copy(files: const [], text: 'x');
    expect(Directory('$root/data/clip').listSync(), isEmpty);
  });

  test('the previous helper is killed before the next starts', () async {
    await owner.copy(files: const [], text: 'one');
    final first = fake.started.single;
    var killedFirst = false;
    final inner = fake.onStart;
    fake.onStart = (c) {
      killedFirst = first.signals.isNotEmpty;
      return inner!(c);
    };
    await owner.copy(files: const [], text: 'two');
    expect(killedFirst, isTrue);
    expect(fake.started, hasLength(2));
  });

  test(
    'a helper that exits before ready is a failure with its stderr',
    () async {
      fake.onStart = (_) => FakeProcess(exit: 1, stderrText: 'no gtk\n');
      await expectLater(
        owner.copy(files: const [], text: 'x'),
        throwsA(
          isA<ClipFailed>().having(
            (e) => e.message,
            'message',
            contains('no gtk'),
          ),
        ),
      );
    },
  );

  test('exit 3 means there is no display', () async {
    fake.onStart = (_) => FakeProcess(exit: 3);
    await expectLater(
      owner.copy(files: const [], text: 'x'),
      throwsA(isA<NoDisplay>()),
    );
  });

  test('no ready within the timeout kills the helper', () async {
    final silent = FakeProcess();
    fake.onStart = (_) => silent;
    await expectLater(
      owner.copy(files: const [], text: 'x'),
      throwsA(isA<ClipFailed>()),
    );
    expect(silent.signals, isNotEmpty);
  });

  test('a helper that cannot start is a failure', () async {
    fake.onStart = (c) => throw ProcessException(c.exe, c.args, 'missing');
    await expectLater(
      owner.copy(files: const [], text: 'x'),
      throwsA(isA<ClipFailed>()),
    );
  });

  test('a helper that quits later (selection taken) is forgotten', () async {
    await owner.copy(files: const [], text: 'one');
    fake.started.single.exitWith(0);
    await settle();
    var killed = false;
    final inner = fake.onStart;
    fake.onStart = (c) {
      killed = fake.started.single.signals.isNotEmpty;
      return inner!(c);
    };
    await owner.copy(files: const [], text: 'two');
    expect(killed, isFalse, reason: 'nothing left to kill');
  });
}
