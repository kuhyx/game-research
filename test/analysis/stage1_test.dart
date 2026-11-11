import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/stage1.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/sampling.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

void main() {
  late Fixture fx;
  late FakeSys fake;
  late Stage1 stage;
  late List<(int, int)> ticks;

  Directory analysis() =>
      Directory(p.join(fx.session.path, 'analysis'))..createSync();

  setUp(() {
    fx = Fixture();
    fake = FakeSys()..onRun = ffmpegFake;
    stage = Stage1(fx.session.path, fake.sys, stillS: 2);
    ticks = [];
  });

  void progress(int d, int t) => ticks.add((d, t));

  group('detect', () {
    test('one decode pass finds cuts and stills and caches them', () async {
      analysis();
      final (scenes, spans) = await stage.detect(40);
      expect(scenes, [15.0]);
      expect(spans.single.start, 3.5);
      final call = fake.calls.single;
      expect(call.args, containsAllInOrder(['-hide_banner', '-nostdin']));
      expect(call.args.join(' '), contains('freezedetect=n=-50dB:d=2.0'));
      expect(fx.out('scenes.json').readAsStringSync(), '[15.0]');
      expect(fx.out('still.jsonl').readAsStringSync(), contains('"end_s":6.5'));

      final (again, spansAgain) = await stage.detect(40);
      expect(again, [15.0]);
      expect(spansAgain.single.end, 6.5);
      expect(fake.calls, hasLength(1), reason: 'cached, no second decode');
    });

    test('the cache tolerates a blank line', () async {
      analysis();
      fx.out('scenes.json').writeAsStringSync('[1, 2.5]');
      fx
          .out('still.jsonl')
          .writeAsStringSync('${jsonEncode({'start_s': 1, 'end_s': 4})}\n\n');
      final (scenes, spans) = await stage.detect(40);
      expect(scenes, [1.0, 2.5]);
      expect(spans.single.length, 3);
      expect(fake.calls, isEmpty);
    });

    test('a failing ffmpeg throws with its stderr', () async {
      analysis();
      fake.onRun = (_) => bad('no such file');
      await expectLater(
        stage.detect(40),
        throwsA(
          isA<StateError>().having(
            (e) => '$e',
            'text',
            contains('no such file'),
          ),
        ),
      );
    });
  });

  group('extractFrames', () {
    const frames = [
      SampleFrame(t: 0, kind: FrameKind.scene, file: 'f_0001.png'),
      SampleFrame(t: 9, kind: FrameKind.scene, file: 'f_0002.png'),
    ];

    test('extracts the missing ones and reports each step', () async {
      final dir = Directory(p.join(fx.session.path, 'analysis', 'frames'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'f_0001.png')).writeAsStringSync('have');
      await stage.extractFrames(frames, progress);
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.args, contains('9.000'));
      expect(File(p.join(dir.path, 'f_0002.png')).existsSync(), isTrue);
      expect(ticks, [(1, 2), (2, 2)]);
    });
  });

  group('clips', () {
    test('a 10 s stream-copied clip per marker, resumable', () async {
      final markers = [
        const Marker(wallUnix: 1, offsetS: 2, tag: MarkerTag.good),
        const Marker(wallUnix: 2, offsetS: 30, tag: MarkerTag.note),
      ];
      final names = await stage.clips(markers);
      expect(names, ['m_01_good.mkv', 'm_02_note.mkv']);
      expect(fake.calls[0].args, containsAllInOrder(['-ss', '0.000']));
      expect(fake.calls[1].args, containsAllInOrder(['-ss', '25.000']));
      expect(fake.calls[1].args, containsAllInOrder(['-t', '10.0']));
      await stage.clips(markers);
      expect(fake.calls, hasLength(2));
    });
  });

  group('contactSheets', () {
    test('tiles the frames once', () async {
      await stage.contactSheets();
      await stage.contactSheets();
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.args.join(' '), contains('tile=4x4'));
    });
  });

  group('run', () {
    final markers = [
      const Marker(wallUnix: 1, offsetS: 12, tag: MarkerTag.good),
    ];

    test('every step, progress up to the total, then a free resume', () async {
      final frames = await stage.run(
        durationS: 40,
        markers: markers,
        progress: progress,
      );
      expect(frames.map((f) => f.kind), [
        FrameKind.scene,
        FrameKind.marker,
        FrameKind.scene,
      ]);
      expect(fx.out('frames.json').readAsStringSync(), contains('f_0003.png'));
      expect(ticks.last, (5, 5));
      expect(ticks.map((t) => t.$1), [1, 2, 3, 4, 5]);
      expect(fx.out('contact/sheet_001.png').existsSync(), isTrue);
      final calls = fake.calls.length;
      await stage.run(durationS: 40, markers: markers, progress: progress);
      expect(fake.calls, hasLength(calls));
    });
  });

  test('integration: real ffmpeg on a 4 s synthetic clip', () async {
    final video = File(p.join(fx.session.path, 'recording.mkv'));
    final made = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-nostdin',
      '-f',
      'lavfi',
      '-i',
      'testsrc=duration=4:size=160x120:rate=10',
      '-c:v',
      'libx264',
      '-y',
      video.path,
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    final real = Stage1(fx.session.path, const Sys(), stillS: 1);
    final frames = await real.run(
      durationS: 4,
      markers: [const Marker(wallUnix: 1, offsetS: 2, tag: MarkerTag.bad)],
      progress: (_, _) {},
    );
    expect(frames, isNotEmpty);
    for (final f in frames) {
      expect(fx.out('frames/${f.file}').existsSync(), isTrue);
    }
    expect(fx.out('clips/m_01_bad.mkv').existsSync(), isTrue);
    expect(
      Directory(p.join(fx.session.path, 'analysis', 'contact')).listSync(),
      isNotEmpty,
    );
  }, timeout: const Timeout(Duration(seconds: 40)));
}
