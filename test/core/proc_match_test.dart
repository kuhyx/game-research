import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/proc_match.dart';

void main() {
  test('matches the reaper AppId token exactly', () {
    const reaper =
        '/home/k/.local/share/Steam/ubuntu12_32/reaper\x00SteamLaunch'
        '\x00AppId=1234\x00--\x00/games/foo.exe\x00';
    expect(cmdlineIsApp(reaper, 1234), isTrue);
    expect(cmdlineIsApp(reaper, 123), isFalse);
    expect(cmdlineIsApp(reaper, 12345), isFalse);
  });

  test('matches an AppId token inside a single argv string', () {
    expect(cmdlineIsApp('reaper SteamLaunch AppId=99 -- x\x00', 99), isTrue);
  });

  test('our own watcher or steam:// uri never counts', () {
    expect(cmdlineIsApp('steam\x00steam://rungameid/99\x00', 99), isFalse);
    expect(cmdlineIsApp('', 99), isFalse);
  });
}
