import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/stage1.dart';
import 'package:game_research/analysis/stills.dart';
import 'package:game_research/core/markers.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

const _markers = [
  Marker(wallUnix: 1, offsetS: 2, tag: MarkerTag.good),
  Marker(wallUnix: 2, offsetS: 30, tag: MarkerTag.note),
];

void main() {
  late Fixture fx;
  late FakeSys fake;

  setUp(() {
    fx = Fixture();
    fake = FakeSys()
      ..onRun = ffmpegFake
      ..onStart = ffmpegStart;
  });

  File still(String name) =>
      File(p.join(fx.session.path, 'analysis', 'clips', name));

  test('one JPEG per marker beside the clips, named like them', () async {
    final names = await extractStills(fake.sys, fx.session.path, _markers);
    expect(names, ['m_01_good.jpg', 'm_02_note.jpg']);
    expect(still('m_01_good.jpg').existsSync(), isTrue);
    expect(still('m_02_note.jpg').existsSync(), isTrue);
    expect(fake.calls[0].args, containsAllInOrder(['-ss', '2.000']));
    expect(fake.calls[1].args, containsAllInOrder(['-ss', '30.000']));
    expect(fake.calls[0].args, containsAllInOrder(['-frames:v', '1']));
    expect(fake.calls[0].args, containsAllInOrder(['-q:v', '2']));
    expect(
      fake.calls[0].args,
      contains(p.join(fx.session.path, 'recording.mkv')),
    );
    expect(
      Directory(p.join(fx.session.path, 'analysis', 'clips'))
          .listSync()
          .map((e) => p.basename(e.path))
          .where((n) => n.contains('.part')),
      isEmpty,
      reason: 'no half-written file is left behind',
    );
  });

  test('a rerun cuts only the missing stills', () async {
    await extractStills(fake.sys, fx.session.path, _markers);
    still('m_02_note.jpg').deleteSync();
    fake.calls.clear();
    final names = await extractStills(fake.sys, fx.session.path, _markers);
    expect(names, hasLength(2));
    expect(fake.calls, hasLength(1));
    expect(fake.calls.single.args, containsAllInOrder(['-ss', '30.000']));
    expect(stillsComplete(fx.session.path, _markers), isTrue);
  });

  test('a failed cut leaves no file and does not throw', () async {
    fake.onRun = (c) {
      ffmpegFake(c);
      return bad('past the end');
    };
    final names = await extractStills(fake.sys, fx.session.path, _markers);
    expect(names, isEmpty);
    expect(stillsComplete(fx.session.path, _markers), isFalse);
    expect(still('m_01_good.jpg.part.jpg').existsSync(), isFalse);
  });

  test(
    'ffmpeg exits 0 but writes nothing: the still is just missing',
    () async {
      fake.onRun = null;
      final names = await extractStills(fake.sys, fx.session.path, _markers);
      expect(names, isEmpty);
    },
  );

  test('the gate is awaited before each cut', () async {
    var gates = 0;
    await extractStills(
      fake.sys,
      fx.session.path,
      _markers,
      gate: () async => gates++,
    );
    expect(gates, 2);
  });

  test('stage 1 cuts the stills where it cuts the clips', () async {
    final stage = Stage1(fx.session.path, fake.sys, stillS: 2);
    await stage.run(durationS: 40, markers: _markers, progress: (_, _) {});
    expect(still('m_01_good.mkv').existsSync(), isTrue);
    expect(still('m_01_good.jpg').existsSync(), isTrue);
    expect(still('m_02_note.jpg').existsSync(), isTrue);
  });
}
