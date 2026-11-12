/// Puts files and text on the X11 CLIPBOARD for a paste into Vesktop.
///
/// A small Python/GTK helper (`helpers/clip_owner.py`) must stay alive to
/// serve the selection, so each copy starts one and the previous one is
/// killed first. Runs on `GAME_RESEARCH_DISPLAY` only (the helper itself
/// refuses `:0` in test mode). Files paste into Chromium as files; its paste
/// event drops the text in the same paste (spike 2026-11-12), so text copies
/// are a separate action.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// The helper could not own the clipboard.
class ClipFailed implements Exception {
  /// Creates the failure.
  const new(this.message);

  /// Why.
  final String message;
}

/// The helper could not open the display.
class NoDisplay extends ClipFailed {
  /// Creates the failure.
  const new(super.message);
}

/// Exit code of the helper when the display cannot be opened.
const kNoDisplayExit = 3;

/// Owns the clipboard through the helper.
class ClipOwner {
  /// Creates the owner; [readyTimeout] is how long the helper may take.
  new(this.config, this.sys, {this.readyTimeout = const Duration(seconds: 5)});

  /// Settings (`clipCmd`, `display`).
  final Config config;

  /// OS seam.
  final Sys sys;

  /// Longest wait for the helper's `ready` line.
  final Duration readyTimeout;

  Process? _helper;

  /// Offers [files] (as a file list) and [text] on the clipboard; returns
  /// once the helper owns it. Throws [NoDisplay] or [ClipFailed].
  Future<void> copy({required List<String> files, required String text}) async {
    _helper?.kill();
    _helper = null;
    final dir = Directory(p.join(config.dataDir, 'clip'))
      ..createSync(recursive: true);
    final textFile = File(
      p.join(dir.path, 'text-${(sys.nowUnix() * 1000).round()}.txt'),
    )..writeAsStringSync(text);
    try {
      _helper = await _launch([
        ...config.clipCmd.skip(1),
        '--text-file',
        textFile.path,
        ...files,
      ]);
    } finally {
      // The helper read it before printing `ready`.
      if (textFile.existsSync()) textFile.deleteSync();
    }
  }

  Future<Process> _launch(List<String> args) async {
    final Process proc;
    try {
      proc = await sys.start(
        config.clipCmd.first,
        args,
        environment: {
          'DISPLAY': config.display,
          if (config.testMode) 'GAME_RESEARCH_TEST': '1',
          if (config.xauthority.isNotEmpty) 'XAUTHORITY': config.xauthority,
        },
      );
    } on ProcessException catch (e) {
      throw ClipFailed('clipboard helper did not start: ${e.message}');
    }
    final ready = Completer<void>();
    final err = StringBuffer();
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      if (line.trim() == 'ready' && !ready.isCompleted) ready.complete();
    });
    proc.stderr.transform(utf8.decoder).listen(err.write);
    unawaited(
      proc.exitCode.then((code) {
        if (identical(_helper, proc)) _helper = null;
        if (ready.isCompleted) return;
        ready.completeError(
          code == kNoDisplayExit
              ? const NoDisplay('no display for the clipboard')
              : ClipFailed('clipboard helper exited $code: $err'.trim()),
        );
      }),
    );
    try {
      await ready.future.timeout(readyTimeout);
    } on TimeoutException {
      proc.kill();
      throw const ClipFailed('clipboard helper never became ready');
    }
    return proc;
  }
}
