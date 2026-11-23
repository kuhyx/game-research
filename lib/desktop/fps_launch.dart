/// MangoHud logging through Steam launch options, the only way the layer
/// loads: never session-wide (kuhy, 2026-11-23: the layer in every Vulkan
/// program aborted sd-cli, llama-server and Steam itself at exit).
///
/// Every installed game gets
/// `MANGOHUD=1 MANGOHUD_CONFIGFILE=<conf> %command%` in front of its options
/// in `localconfig.vdf`, written only while no Steam client runs (Steam
/// rewrites the file on exit and would drop the edit). The wrapper writes
/// them at start and before each launch, so a session started while Steam
/// is up is covered by an earlier write.
library;

import 'dart:io';

import 'package:game_research/core/steam_vdf.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/proc_scan.dart';
import 'package:game_research/desktop/steam_library.dart';
import 'package:path/path.dart' as p;

/// Writes the launch options for one wrapper.
class FpsLaunch {
  /// Creates the writer.
  const new(this.config, this.log);

  /// Settings.
  final Config config;

  /// Event log.
  final EventLog log;

  /// Where MangoHud writes its CSVs.
  String get spoolDir => p.join(config.dataDir, 'fps-spool');

  /// The MangoHud config this app owns (kuhy's own is never touched).
  String get confPath => p.join(config.dataDir, 'mangohud.conf');

  /// Puts MangoHud logging into the launch options of every installed game
  /// and of [appid] (the game about to launch; null at wrapper start). Never
  /// throws: each account file gets one `fps_launch_option` event whose
  /// `result` is [appid]'s outcome (`all` without one) and whose `games`
  /// counts the outcomes.
  void prepare([int? appid]) {
    void event(String result, [Map<String, Object?> extra = const {}]) =>
        log.event('fps_launch_option', {
          'appid': ?appid,
          'result': result,
          ...extra,
        });
    final skip = _skipReason();
    if (skip != null) return event(skip);
    final files = _localconfigs();
    if (files.isEmpty) return event('skipped no localconfig');
    try {
      _writeConf();
    } on FileSystemException catch (e) {
      return event('error', {'message': 'mangohud.conf: ${e.message}'});
    }
    final ids = {
      ?appid,
      for (final g in SteamLibrary(config.steamRoot).games()) g.appid,
    };
    for (final f in files) {
      try {
        final before = f.readAsStringSync();
        var text = before;
        final games = <String, int>{};
        String? mine;
        for (final id in ids) {
          final edit = addMangoHud(text, id, confPath);
          text = edit.text;
          games.update(edit.result, (n) => n + 1, ifAbsent: () => 1);
          if (id == appid) mine = edit.result;
        }
        if (text != before) _replace(f, text);
        event(mine ?? 'all', {'games': games});
      } on FormatException catch (e) {
        event('error', {'message': e.message});
      } on FileSystemException catch (e) {
        event('error', {'message': e.message});
      }
    }
  }

  /// Why nothing may be written now, or null. A scratch data dir (playstudy,
  /// any off-screen run) never edits kuhy's real Steam config: its options
  /// would point games at a config that is deleted later.
  String? _skipReason() {
    final realSteam = p.join(config.home, '.local', 'share', 'Steam');
    final realData = p.join(config.home, 'data', 'game-research');
    if (_same(config.steamRoot, realSteam) &&
        !_same(config.dataDir, realData)) {
      return 'skipped scratch data';
    }
    final steam = ProcScan(config.procRoot).steamClient(config.steamPidFile);
    return steam == null ? null : 'skipped steam running';
  }

  /// Whether [a] and [b] name one folder (symlinks such as `~/.steam/steam`
  /// resolved when they exist).
  static bool _same(String a, String b) {
    String real(String path) => Directory(path).existsSync()
        ? Directory(path).resolveSymbolicLinksSync()
        : p.normalize(path);
    return real(a) == real(b);
  }

  /// Every account's `localconfig.vdf`, sorted.
  List<File> _localconfigs() {
    final users = Directory(p.join(config.steamRoot, 'userdata'));
    return [
        if (users.existsSync())
          for (final d in users.listSync().whereType<Directory>())
            File(p.join(d.path, 'config', 'localconfig.vdf')),
      ].where((f) => f.existsSync()).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  /// Renders `tool/mangohud.conf.in` into [confPath].
  void _writeConf() {
    final template = File(p.join(config.repo, 'tool', 'mangohud.conf.in'))
        .readAsStringSync();
    final text = template.replaceAll('@SPOOL@', spoolDir);
    Directory(spoolDir).createSync(recursive: true);
    final conf = File(confPath);
    if (!conf.existsSync() || conf.readAsStringSync() != text) {
      conf.writeAsStringSync(text);
    }
  }

  /// Writes [text] over [file] through a rename, keeping the first original
  /// as `<file>.game-research.bak`.
  void _replace(File file, String text) {
    final bak = File('${file.path}.game-research.bak');
    if (!bak.existsSync()) file.copySync(bak.path);
    File('${file.path}.game-research.tmp')
      ..writeAsStringSync(text)
      ..renameSync(file.path);
  }
}
