import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/notes_api.dart';
import 'package:game_research/desktop/session_store.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory root;
  late FakeSys fake;
  late NotesApi api;
  late String data;

  setUp(() {
    root = tempDir();
    final config = testConfig(root);
    data = config.dataDir;
    fake = FakeSys()
      ..onRun = (c) {
        File(c.args.last).writeAsStringSync('jpeg');
        return null;
      };
    api = NotesApi(
      config,
      fake.sys,
      SessionStore(config),
      EventLog(config.logFile),
    );
  });

  /// A session folder; [started] is local time.
  Directory session(
    String id,
    String game,
    DateTime? started,
    List<Marker> markers, {
    bool video = true,
  }) {
    final dir = Directory(p.join(data, id))..createSync(recursive: true);
    File(p.join(dir.path, 'session.json')).writeAsStringSync(
      jsonEncode({
        'game': game,
        if (started != null)
          'started_unix': started.millisecondsSinceEpoch / 1e3,
      }),
    );
    File(p.join(dir.path, 'markers.jsonl'))
        .writeAsStringSync(markers.map((m) => '${m.toLine()}\n').join());
    if (video) File(p.join(dir.path, 'recording.mkv')).writeAsStringSync('v');
    return dir;
  }

  const good = Marker(
    wallUnix: 1,
    offsetS: 65,
    tag: MarkerTag.good,
    note: 'n1',
  );
  const bad = Marker(wallUnix: 2, offsetS: 90, tag: MarkerTag.bad);
  final d1 = DateTime(2026, 11, 10, 20);
  final d2 = DateTime(2026, 11, 11, 21);

  test('every session of the game, oldest first, analysed or not', () {
    session('20261111-210000-alpha', 'Alpha', d2, [bad]);
    session('20261110-200000-alpha', 'Alpha', d1, [good]);
    session('20261110-210000-beta', 'Beta', d1, [good]);
    Directory(p.join(data, 'stray')).createSync();
    Directory(p.join(data, 'games')).createSync();
    final out = api.notes('alpha', 'Alpha');
    final parts = out['parts']! as List<Object?>;
    final part = parts.single! as Map<String, Object?>;
    expect(out['slug'], 'alpha');
    expect([part['n'], part['of']], [1, 1]);
    expect(part['text'], contains('**Alpha** · my notes 1/1'));
    final markers = part['markers']! as List<Object?>;
    expect(
      [for (final m in markers) (m! as Map)['session']],
      ['20261110-200000-alpha', '20261111-210000-alpha'],
    );
    expect(markers.first, {
      'session': '20261110-200000-alpha',
      'i': 1,
      'tag': 'good',
      'time': '0:01:05',
      'note': 'n1',
      'line': '👍 `0:01:05` n1',
      'still': false,
    });
  });

  test('no data folder, no sessions: no parts', () {
    expect(api.notes('alpha', 'Alpha'), {'slug': 'alpha', 'parts': <Object>[]});
  });

  test('a session without started_unix is dated by its file', () {
    session('20261110-200000-alpha', 'Alpha', null, [good]);
    final text = (api.notes('alpha', 'Alpha')['parts']! as List).single as Map;
    expect(text['text'], contains('__20'));
  });

  test(
    'missing stills are cut in the background; still:false until then',
    () async {
      final dir = session('20261110-200000-alpha', 'Alpha', d1, [good, bad]);
      Map<String, Object?> first() =>
          ((api.notes('alpha', 'Alpha')['parts']! as List).single as Map)
              .cast();
      expect(
        [for (final m in first()['markers']! as List) (m as Map)['still']],
        [false, false],
      );
      await api.idle;
      expect(fake.of('ffmpeg'), hasLength(2));
      expect(
        File(p.join(dir.path, 'analysis', 'clips', 'm_02_bad.jpg'))
            .existsSync(),
        isTrue,
      );
      expect(
        [for (final m in first()['markers']! as List) (m as Map)['still']],
        [true, true],
      );
      await api.idle;
      expect(fake.of('ffmpeg'), hasLength(2), reason: 'nothing left to cut');
    },
  );

  test('two reads at once queue one extraction', () async {
    session('20261110-200000-alpha', 'Alpha', d1, [good]);
    api
      ..notes('alpha', 'Alpha')
      ..notes('alpha', 'Alpha');
    await api.idle;
    expect(fake.of('ffmpeg'), hasLength(1));
  });

  test('no recording.mkv: nothing to cut', () async {
    session('20261110-200000-alpha', 'Alpha', d1, [good], video: false);
    api.notes('alpha', 'Alpha');
    await api.idle;
    expect(fake.calls, isEmpty);
  });

  test('a live recording.pid holds extraction back', () async {
    session('20261110-200000-alpha', 'Alpha', d1, [good]);
    File(p.join(data, 'recording.pid')).writeAsStringSync('$pid');
    api.notes('alpha', 'Alpha');
    await api.idle;
    expect(fake.calls, isEmpty);
    File(p.join(data, 'recording.pid')).deleteSync();
    api.notes('alpha', 'Alpha');
    await api.idle;
    expect(fake.calls, hasLength(1));
  });

  test('an ffmpeg that cannot start is logged, not thrown', () async {
    session('20261110-200000-alpha', 'Alpha', d1, [good]);
    fake.onRun = (c) => throw ProcessException(c.exe, c.args, 'gone');
    api.notes('alpha', 'Alpha');
    await api.idle;
    final log = File(p.join(data, 'playstudy.jsonl')).readAsStringSync();
    expect(log, contains('"event":"stills"'));
    expect(log, contains('gone'));
  });

  test('stillFile: the JPEG of a marker, null for anything else', () {
    final dir = session('20261110-200000-alpha', 'Alpha', d1, [good, bad]);
    File(p.join(dir.path, 'analysis', 'clips', 'm_02_bad.jpg'))
      ..createSync(recursive: true)
      ..writeAsStringSync('jpeg');
    expect(
      api.stillFile('20261110-200000-alpha', 2)?.readAsStringSync(),
      'jpeg',
    );
    expect(
      api.stillFile('20261110-200000-alpha', 1),
      isNull,
      reason: 'not cut',
    );
    expect(api.stillFile('20261110-200000-alpha', 0), isNull);
    expect(api.stillFile('20261110-200000-alpha', 3), isNull);
    expect(api.stillFile('nope', 1), isNull);
    expect(api.stillFile('../x', 1), isNull);
  });

  test('line of one marker', () {
    session('20261110-200000-alpha', 'Alpha', d1, [good, bad]);
    expect(api.markerLine('20261110-200000-alpha', 2), '👎 `0:01:30`');
    expect(api.markerLine('20261110-200000-alpha', 9), isNull);
    expect(api.markerLine('nope', 1), isNull);
  });
}
