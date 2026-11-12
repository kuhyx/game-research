import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/fps.dart';

void main() {
  // 98 frames of 10 ms, one of 20 ms, one of 50 ms; the log lasts 1.05 s.
  final csv = File('test/fixtures/mangohud_0.8.csv').readAsStringSync();

  group('FpsLog.parse', () {
    test('reads frametime and elapsed by header name', () {
      final log = FpsLog.parse(csv)!;
      expect(log.frametimesMs.length, 100);
      expect(log.frametimesMs.last, 50);
      expect(log.elapsedNs.last, 1050000000);
      expect(log.durationS, closeTo(1.05, 1e-9));
    });

    test('skips the versioned preamble and malformed rows', () {
      const text = '''
v1
0.8.4
---------------------SYSTEM INFO---------------------
os,cpu
Arch,Ryzen
--------------------FRAME METRICS--------------------
fps,frametime,cpu_load,elapsed
100,10,1,10000000
garbage
100,0,1,20000000
50,20,1,40000000
''';
      final log = FpsLog.parse(text)!;
      expect(log.frametimesMs, [10, 20]);
      expect(log.elapsedNs, [10000000, 40000000]);
    });

    test('is null without a frame-metrics header', () {
      expect(FpsLog.parse(''), isNull);
      expect(FpsLog.parse('os,cpu\nArch,Ryzen\n'), isNull);
      expect(FpsLog.parse('fps,cpu_load\n1,2\n'), isNull);
    });

    test('is null when no row parses', () {
      expect(FpsLog.parse('fps,frametime,elapsed\nx,y,z\n'), isNull);
    });
  });

  group('fpsStats', () {
    test('avg, 1% low, min and count from frametimes', () {
      final s = fpsStats(FpsLog.parse(csv)!.frametimesMs)!;
      expect(s.samples, 100);
      expect(s.avg, 95.2);
      expect(s.p1Low, 50.0);
      expect(s.min, 20.0);
      expect(s.toJson(), {
        'avg': 95.2,
        'p1_low': 50.0,
        'min': 20.0,
        'samples': 100,
      });
    });

    test('is null with no frames', () {
      expect(fpsStats(const []), isNull);
    });

    test('one frame: every figure is that frame', () {
      final s = fpsStats(const [16.0])!;
      expect((s.avg, s.p1Low, s.min, s.samples), (62.5, 62.5, 62.5, 1));
    });
  });

  group('window', () {
    final log = FpsLog.parse(csv)!;

    test('the log spans [end - duration, end]', () {
      expect(log.overlaps(fileEndUnix: 2000.05, from: 1999.5, to: 2500), true);
      expect(log.overlaps(fileEndUnix: 2000.05, from: 0, to: 1999), false);
      expect(
        log.overlaps(fileEndUnix: 2000.05, from: 2000.06, to: 3000),
        false,
      );
    });

    test('frametimesBetween keeps the samples inside the session', () {
      final all = log.frametimesBetween(
        fileEndUnix: 2000.05,
        from: 0,
        to: 9000000000,
      );
      expect(all.length, 100);
      // elapsed >= 495 ms: 49 ten-ms frames, the 20 ms and the 50 ms one
      final tail = log.frametimesBetween(
        fileEndUnix: 2000.05,
        from: 1999.495,
        to: 9000000000,
      );
      expect(tail.length, 51);
      expect(tail.last, 50);
      expect(
        log.frametimesBetween(fileEndUnix: 2000.05, from: 0, to: 1999),
        isEmpty,
      );
    });
  });
}
