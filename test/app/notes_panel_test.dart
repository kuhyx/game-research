import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/marker_style.dart';

import 'fake_wrapper.dart';
import 'notes_fixtures.dart';
import 'reader_fixtures.dart';

Finder label(String l) => find.bySemanticsLabel(RegExp('^${RegExp.escape(l)}'));

Finder tagIcon(int k) => find.byWidgetPredicate(
  (w) =>
      w is Icon &&
      w.icon == kMarkerStyles[k].icon &&
      w.color == kMarkerStyles[k].color,
);

int notesGets(FakeWrapper w) =>
    w.calls.where((c) => c == 'GET /api/games/1/notes').length;

void main() {
  setUpAll(loadInter);

  group('layout', () {
    testWidgets('a header per part, a row per marker, a date per session', (
      t,
    ) async {
      final w = FakeWrapper()..noteParts = twoParts();
      await openNotes(t, w);
      expect(t.takeException(), isNull);
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('2026-11-10'), findsOneWidget);
      expect(find.text('2026-11-11'), findsNWidgets(2), reason: 'per part');
      expect(find.text('0:01:05'), findsOneWidget);
      expect(find.text('nice shelf'), findsOneWidget);
      expect(find.text('1:02:03'), findsOneWidget);
      expect(tagIcon(0), findsOneWidget);
      expect(tagIcon(1), findsOneWidget);
      expect(tagIcon(2), findsOneWidget);
      expect(
        find.byIcon(Icons.edit_note_rounded),
        findsOneWidget,
        reason: 'an unknown tag falls back to the note look',
      );
      for (final l in [
        'copy notes 1 files',
        'copy notes 1 text',
        'copy notes 2 files',
        'copy notes 2 text',
        'copy marker $stampA 1',
        'copy marker $stampA 2',
        'copy marker $stampB 1',
        'copy marker $stampB 2',
        'close',
      ]) {
        expect(label(l), findsOneWidget, reason: l);
      }
      await endNotes(t);
    });

    testWidgets('fits a 4K window at both pixel ratios and a small one', (
      t,
    ) async {
      for (final (size, dpr) in [
        (const Size(3840, 2160), 2.0),
        (const Size(3840, 2160), 1.0),
        (const Size(1280, 720), 1.0),
      ]) {
        final w = FakeWrapper()..noteParts = twoParts();
        await openNotes(t, w, size: size, dpr: dpr);
        expect(t.takeException(), isNull, reason: '$size @$dpr');
        await endNotes(t);
      }
    });

    testWidgets('a failed load shows the error glyph, no parts the empty one', (
      t,
    ) async {
      final w = FakeWrapper()..getStatus = 500;
      await openNotes(t, w);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      await endNotes(t);
      final empty = FakeWrapper();
      await openNotes(t, empty);
      expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
      await endNotes(t);
    });

    testWidgets('the close icon and Esc call back', (t) async {
      var closed = 0;
      final w = FakeWrapper()..noteParts = twoParts();
      await openNotes(t, w, onClose: () => closed++);
      await t.tap(label('close'));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 2);
      await endNotes(t);
    });
  });

  group('copying', () {
    testWidgets('files, text and marker icons post their own call', (t) async {
      final w = FakeWrapper()..noteParts = twoParts();
      await openNotes(t, w);
      await t.tap(label('copy notes 1 files'));
      await t.pump();
      await t.pump();
      await t.tap(label('copy notes 2 text'));
      await t.pump();
      await t.pump();
      await t.tap(label('copy marker $stampB 1'));
      await t.pump();
      await t.pump();
      expect(w.calls.where((c) => c.startsWith('POST')), [
        'POST /api/games/1/notes/1/copy?what=files',
        'POST /api/games/1/notes/2/copy?what=text',
        'POST /api/sessions/$stampB/markers/1/copy',
      ]);
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));
      await t.pump(const Duration(seconds: 2));
      await endNotes(t);
    });

    testWidgets('a copy refused by the wrapper shows the error glyph', (
      t,
    ) async {
      final w = FakeWrapper()
        ..noteParts = twoParts()
        ..postStatus = 409;
      await openNotes(t, w);
      await t.tap(label('copy notes 1 text'));
      await t.pump();
      await t.pump();
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      await endNotes(t);
    });

    testWidgets('files and marker copies are off while nothing is cut', (
      t,
    ) async {
      final w = FakeWrapper()..noteParts = twoParts(still: false);
      await openNotes(t, w);
      await t.tap(label('copy notes 1 files'), warnIfMissed: false);
      await t.tap(label('copy marker $stampA 1'), warnIfMissed: false);
      await t.tap(label('copy notes 1 text'));
      await t.pump();
      await t.pump();
      expect(w.calls.where((c) => c.startsWith('POST')), [
        'POST /api/games/1/notes/1/copy?what=text',
      ]);
      await t.pump(const Duration(seconds: 2));
      await endNotes(t);
    });

    testWidgets('a spinner shows while the wrapper works', (t) async {
      final gate = Completer<void>();
      final w = FakeWrapper()
        ..noteParts = twoParts()
        ..copyGate = gate;
      await openNotes(t, w);
      await t.tap(label('copy notes 1 files'));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete();
      await t.pump();
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      await endNotes(t);
    });
  });

  group('stills', () {
    testWidgets('a cut still is an image of the still endpoint', (t) async {
      final w = FakeWrapper()..noteParts = twoParts();
      await openNotes(t, w);
      final urls = [
        for (final i in t.widgetList<Image>(find.byType(Image)))
          ((i.image as ResizeImage).imageProvider as NetworkImage).url,
      ];
      expect(urls, [
        'http://127.0.0.1:1/api/sessions/$stampA/still/1',
        'http://127.0.0.1:1/api/sessions/$stampA/still/2',
        'http://127.0.0.1:1/api/sessions/$stampB/still/1',
        'http://127.0.0.1:1/api/sessions/$stampB/still/2',
      ]);
      await endNotes(t);
    });

    testWidgets('a still that cannot be loaded shows the broken glyph', (
      t,
    ) async {
      final w = FakeWrapper()..noteParts = twoParts();
      await openNotes(t, w);
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.broken_image_rounded), findsWidgets);
      await endNotes(t);
    });

    testWidgets('waiting stills show a placeholder and are polled for', (
      t,
    ) async {
      final w = FakeWrapper()..noteParts = twoParts(still: false);
      await openNotes(t, w);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsNWidgets(4));
      expect(find.byType(Image), findsNothing);
      expect(notesGets(w), 1);
      w.noteParts = twoParts();
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(notesGets(w), 2);
      expect(find.byType(Image), findsNWidgets(4));
      expect(find.byIcon(Icons.hourglass_top_rounded), findsNothing);
      await t.pump(const Duration(seconds: 10));
      expect(notesGets(w), 2, reason: 'all cut: polling stops');
      await endNotes(t);
    });

    testWidgets('polling gives up after maxPolls', (t) async {
      final w = FakeWrapper()..noteParts = twoParts(still: false);
      await openNotes(t, w);
      for (var k = 0; k < 8; k++) {
        await t.pump(const Duration(seconds: 2));
      }
      expect(notesGets(w), 4, reason: 'the first read plus maxPolls');
      await endNotes(t);
    });

    testWidgets('a failing re-poll keeps the parts on screen', (t) async {
      final w = FakeWrapper()..noteParts = twoParts(still: false);
      await openNotes(t, w);
      w.getStatus = 500;
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(find.text('0:01:05'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      await endNotes(t);
    });

    testWidgets('closing while a poll is pending cancels it', (t) async {
      final w = FakeWrapper()..noteParts = twoParts(still: false);
      await openNotes(t, w);
      await endNotes(t);
      await t.pump(const Duration(seconds: 10));
      expect(notesGets(w), 1);
    });
  });
}
