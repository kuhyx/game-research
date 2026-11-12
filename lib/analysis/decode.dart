/// The stage 1 decode pass: one ffmpeg run whose `-progress` output is read
/// while it works, so the progress ring moves (kuhy, 2026-11-12: stage 1
/// reported nothing for the ~1.6 CPU-s per video second it takes).
library;

import 'dart:convert';

import 'package:game_research/desktop/sys.dart';

/// Stage 1 reports progress in this many units: the decode is the bulk of
/// the time (~1.6 CPU-s per video second), the rest shares the remainder.
const kStageUnits = 1000;

/// The decode's share of [kStageUnits].
const kDecodeUnits = 900;

/// Units done by an ffmpeg `-progress` line, or null for any other line.
/// `out_time_us` is absolute (`-copyts`), so it is clamped to the duration.
int? decodeUnits(String line, double durationS) {
  if (durationS <= 0 || !line.startsWith('out_time_us=')) return null;
  final us = int.tryParse(line.substring('out_time_us='.length));
  if (us == null) return null;
  final fraction = (us / 1e6 / durationS).clamp(0.0, 1.0);
  return (fraction * kDecodeUnits).round();
}

/// Runs the decode, handing each `-progress` stdout line to [onLine] while it
/// works;
/// returns stderr (the filter log). Throws on a non-zero exit.
Future<String> runDecode(
  Sys sys,
  List<String> args,
  void Function(String) onLine,
) async {
  final all = ['-hide_banner', '-nostdin', ...args];
  final proc = await sys.start('ffmpeg', all);
  final lines = proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach(onLine);
  final err = proc.stderr.transform(utf8.decoder).join();
  final code = await proc.exitCode;
  await lines;
  final log = await err;
  if (code != 0) {
    throw StateError('ffmpeg ${args.take(6).join(' ')}: $log');
  }
  return log;
}
