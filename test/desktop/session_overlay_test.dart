import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/xrandr.dart';
import 'package:game_research/desktop/session_services.dart';

import '../support/fakes.dart';

const _output = Output(name: 'DP-2', width: 3840, height: 2160, x: 5);

void main() {
  late FakeSys fake;
  late Directory root;

  setUp(() {
    root = tempDir();
    fake = FakeSys();
  });

  group('Overlay', () {
    Overlay overlay([Map<String, String> extra = const {}]) =>
        Overlay(testConfig(root, extra: extra), fake.sys);

    test('start launches the Tk helper over the output', () async {
      fake.onStart = (_) => FakeProcess();
      await overlay().start(_output);
      final call = fake.calls.single;
      expect(call.exe, 'python3');
      expect(call.args.first, endsWith('helpers/flash_overlay.py'));
      expect(call.args, containsAllInOrder(['--geometry', '3840x2160+5+0']));
      expect(call.args, containsAllInOrder(['--thickness', '12']));
      expect(call.env, {'DISPLAY': ':99'});
    });

    test('mark flashes the colour and plays the tick detached', () async {
      fake.onStart = (c) => c.exe == 'python3' ? FakeProcess() : null;
      final o = overlay();
      await o.start(_output);
      await o.mark(MarkerTag.bad);
      await settle();
      expect(fake.started.first.stdinText, '#e2302f\n');
      final tick = fake.calls.last;
      expect(tick.exe, 'faketick');
      expect(tick.args, ['bad']);
      expect(tick.mode, ProcessStartMode.detached);
    });

    test('mark works without a helper and without a tick command', () async {
      final o = overlay({'GAME_RESEARCH_TICK_CMD': ' '});
      await o.mark(MarkerTag.good);
      expect(fake.calls, isEmpty);
    });

    test('a tick command with arguments keeps them before the tag', () async {
      await overlay({'GAME_RESEARCH_TICK_CMD': 'play -q'}).mark(MarkerTag.note);
      expect(fake.calls.single.args, ['-q', 'note']);
    });

    test('a missing player does not fail the marker', () async {
      fake.onStart = (_) => throw const ProcessException('faketick', []);
      await overlay().mark(MarkerTag.confusing);
      expect(fake.calls, hasLength(1));
    });

    test('stop closes stdin, kills the helper and is idempotent', () async {
      final helper = FakeProcess();
      fake.onStart = (_) => helper;
      final o = overlay();
      await o.stop();
      await o.start(_output);
      await o.stop();
      await o.stop();
      expect(helper.signals, hasLength(1));
    });
  });

  group('NoteAsker', () {
    NoteAsker asker() => NoteAsker(testConfig(root), fake.sys);

    test('returns the first typed line, trimmed', () async {
      fake.onStart = (_) =>
          FakeProcess(exit: 0, stdoutText: '  a note \nmore\n');
      expect(await asker().ask(), 'a note');
      final call = fake.calls.single;
      expect(call.exe, 'dmenu');
      expect(call.args, containsAllInOrder(['-p', '']));
      expect(call.env, {'DISPLAY': ':99'});
    });

    test('Escape (no output) gives an empty note', () async {
      fake.onStart = (_) => FakeProcess(exit: 1);
      expect(await asker().ask(), '');
    });

    test('a missing dmenu gives an empty note', () async {
      fake.onStart = (_) => throw const ProcessException('dmenu', []);
      expect(await asker().ask(), '');
    });

    test('cancelAll closes an open line', () async {
      final dmenu = FakeProcess();
      fake.onStart = (_) => dmenu;
      final a = asker();
      final pending = a.ask();
      await settle();
      a.cancelAll();
      expect(await pending, '');
      expect(dmenu.signals, [ProcessSignal.sigterm]);
      a.cancelAll();
      expect(dmenu.signals, hasLength(1));
    });
  });
}
