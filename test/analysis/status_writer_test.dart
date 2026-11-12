import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/job.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/core/usage.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late File file;
  late StatusWriter writer;

  Map<String, Object?> read() =>
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

  setUp(() {
    file = File(p.join(tempDir().path, 'status.json'));
    writer = StatusWriter(file, FakeSys().sys, () => Usage.zero);
  });

  test('waiting in the stage that ran keeps its done/total and ring', () {
    writer
      ..write(2, 5, 40, StageState.running)
      ..write(
        2,
        0,
        1,
        StageState.waiting,
        error: 'usage limit',
        retryAfterS: 60,
      );
    final s = read();
    expect([s['state'], s['done'], s['total']], ['waiting', 5, 40]);
    expect(s['progress'], closeTo((1 + 5 / 40) / 3, 1e-9));
    expect(s['eta_s'], isNull);
  });

  test('waiting before any stage ran (queued) stays at the start', () {
    writer.write(0, 0, 1, StageState.waiting, error: 'queued behind x');
    expect(read()['progress'], 0);
  });

  test('waiting in a later stage than the last report uses the given one', () {
    writer
      ..write(1, 1000, 1000, StageState.running)
      ..write(2, 0, 1, StageState.waiting, error: 'no tier');
    expect(read()['progress'], closeTo(1 / 3, 1e-9));
  });
}
