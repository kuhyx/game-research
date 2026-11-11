/// Recognising the running game in `/proc/<pid>/cmdline`.
///
/// Steam starts every game under its reaper:
/// `reaper SteamLaunch AppId=<id> -- <game>`, so the token `AppId=<id>`
/// marks the game's process tree for its whole life, Proton included.
library;

/// Whether a NUL-separated [cmdline] carries the exact token `AppId=<appid>`.
bool cmdlineIsApp(String cmdline, int appid) {
  final token = 'AppId=$appid';
  for (final arg in cmdline.split('\x00')) {
    for (final word in arg.split(' ')) {
      if (word == token) return true;
    }
  }
  return false;
}
