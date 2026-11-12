/// A [ServerHarness] with one Librarian session of two markers, a fake
/// clipboard helper and a fake ffmpeg that cuts stills.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/markers.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';
import 'server_harness.dart';

const _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 7];

/// The share routes under test.
class ShareHarness {
  new _(this.s);

  /// Session folder name.
  static const id = '20261110-200000-librarian';

  /// Steam app id of the game.
  static const appid = 4197610;

  /// Starts the server, the fakes and the session.
  static Future<ShareHarness> start() async {
    final x = ShareHarness._(
      await ServerHarness.start(games: {appid: 'Librarian'}),
    );
    final inner = x.s.h.fake.onStart;
    x.s.h.fake.onStart = (c) {
      if (c.exe != '/usr/bin/python3') return inner!(c);
      final i = c.args.indexOf('--text-file');
      x.starts.add((
        c.args.sublist(i + 2),
        File(c.args[i + 1]).readAsStringSync(),
      ));
      return x.helper(c);
    };
    final run = x.s.h.fake.onRun;
    x.s.h.fake.onRun = (c) {
      if (c.exe == '/usr/bin/python3') return x.caption(c);
      if (c.exe != 'ffmpeg' || c.args.last.endsWith('.chapters.mkv')) {
        return run!(c);
      }
      // A still: `<name>.jpg.part.jpg`.
      if (c.args.last.endsWith('.jpg')) {
        File(c.args.last).writeAsBytesSync(_jpeg);
      }
      return null;
    };
    x.session = Directory(p.join(x.s.h.config.dataDir, id))
      ..createSync(recursive: true);
    File(p.join(x.session.path, 'session.json')).writeAsStringSync(
      jsonEncode({
        'game': 'Librarian',
        'started_unix': DateTime(2026, 11, 10, 20).millisecondsSinceEpoch / 1e3,
      }),
    );
    const markers = [
      Marker(wallUnix: 1, offsetS: 65, tag: MarkerTag.good, note: 'nice'),
      Marker(wallUnix: 2, offsetS: 90, tag: MarkerTag.bad),
    ];
    File(p.join(x.session.path, 'markers.jsonl'))
        .writeAsStringSync(markers.map((m) => '${m.toLine()}\n').join());
    File(p.join(x.session.path, 'recording.mkv')).writeAsStringSync('v');
    return x;
  }

  /// The server and its client.
  final ServerHarness s;

  /// The session folder.
  late final Directory session;

  /// Each helper start: (file arguments, text file content).
  final starts = <(List<String>, String)>[];

  /// Each captioner run's jobs (decoded `*.jobs.json`).
  final captions = <List<Map<String, Object?>>>[];

  /// Makes the captioner fail with this exit code (null = it works).
  int? captionExit;

  /// The captioner: writes each `out` as `cap|<time>|<note>|<right>|` plus
  /// the source bytes, so a test sees what the band would say.
  ProcessResult caption(Call c) {
    if (captionExit != null) return ProcessResult(1, captionExit!, '', 'boom');
    final jobs = [
      for (final j in jsonDecode(File(c.args.last).readAsStringSync()) as List)
        (j as Map).cast<String, Object?>(),
    ];
    captions.add(jobs);
    for (final j in jobs) {
      File(j['out']! as String).writeAsBytesSync([
        ...utf8.encode('cap|${j['time']}|${j['note']}|${j['right']}|'),
        ...File(j['src']! as String).readAsBytesSync(),
      ]);
    }
    return ProcessResult(1, 0, '', '');
  }

  /// What the helper process does.
  FakeProcess Function(Call) helper = (_) => FakeProcess(stdoutText: 'ready\n');

  /// A file of the session's `analysis/clips`.
  File stillOf(String name) =>
      File(p.join(session.path, 'analysis', 'clips', name));

  /// Both stills exist.
  void cutStills() {
    stillOf('m_01_good.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jpeg);
    stillOf('m_02_bad.jpg').writeAsBytesSync(_jpeg);
  }

  /// A second Librarian session [id] (started 2026-11-09) with one marker
  /// whose still is [cut]: its stills are also named `m_01_<tag>.jpg`.
  Directory addEarlierSession(String id, {required bool cut}) {
    final dir = Directory(p.join(s.h.config.dataDir, id))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'session.json')).writeAsStringSync(
      jsonEncode({
        'game': 'Librarian',
        'started_unix': DateTime(2026, 11, 9, 20).millisecondsSinceEpoch / 1e3,
      }),
    );
    const marker = Marker(wallUnix: 1, offsetS: 10, tag: MarkerTag.good);
    File(p.join(dir.path, 'markers.jsonl'))
        .writeAsStringSync('${marker.toLine()}\n');
    File(p.join(dir.path, 'recording.mkv')).writeAsStringSync('v');
    if (cut) {
      File(p.join(dir.path, 'analysis', 'clips', 'm_01_good.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xFF, 0xD8, 9]);
    }
    return dir;
  }

  /// `POST` [path].
  Future<Reply> post(String path) => s.hit('POST', path);

  /// A session starts recording.
  Future<void> startRecording() async {
    await post('/api/start?appid=$appid');
    s.h.gameRuns(appid);
    for (var i = 0; i < 100 && !s.h.controller.recording; i++) {
      await settle();
    }
  }
}
