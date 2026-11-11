/// Every knob of the wrapper and the analyzer, read from the environment.
///
/// Defaults are kuhy's real setup; the `GAME_RESEARCH_*` variables are the
/// seams tests and the E2E use to point everything at scratch data, a fake
/// Steam, fake models and a private Xvfb. With `GAME_RESEARCH_TEST=1` the
/// wrapper refuses display `:0` (kuhy's live screen) outright.
library;

import 'package:path/path.dart' as p;

/// Fixed on purpose: the origin keys the Chrome profile (zoom, page state),
/// so a different port is a fresh, empty app. Free on this PC 2026-11-11
/// (8791 is taken; 8730-8799 are mostly other apps').
const kDefaultPort = 8805;

/// The settings of one process.
class Config {
  /// Builds the config from [env] (normally `Platform.environment`).
  factory fromEnv(Map<String, String> env, {required String cwd}) {
    final home = env['HOME'] ?? '/';
    String get(String key, String fallback) {
      final v = env['GAME_RESEARCH_$key'];
      return v == null || v.isEmpty ? fallback : v;
    }

    final share = p.join(home, '.local', 'share', 'game-research');
    final data = get('DATA', p.join(home, 'data', 'game-research'));
    final config = Config._(
      home: home,
      repo: get('REPO', cwd),
      port: int.tryParse(get('PORT', '')) ?? kDefaultPort,
      dataDir: data,
      logFile: get('LOG', p.join(data, 'playstudy.jsonl')),
      autostartS: double.tryParse(get('AUTOSTART_S', '')) ?? 3,
      defaultAppid: int.tryParse(get('DEFAULT_APPID', '')) ?? 4197610,
      windowTimeoutS: double.tryParse(get('WINDOW_TIMEOUT_S', '')) ?? 900,
      relaunchS: double.tryParse(get('RELAUNCH_S', '')) ?? 30,
      steamPidFile: get('STEAM_PID', p.join(home, '.steam', 'steam.pid')),
      steamEnv: _words(get('STEAM_ENV', '')),
      xauthority: env['XAUTHORITY'] ?? '',
      procRoot: get('PROC', '/proc'),
      steamRoot: get('STEAM_ROOT', p.join(home, '.local', 'share', 'Steam')),
      steamCmd: get('STEAM_CMD', 'steam'),
      display: get('DISPLAY', env['DISPLAY'] ?? ':0'),
      output: get('OUTPUT', ''),
      audio: get('AUDIO', 'default'),
      fps: int.tryParse(get('FPS', '')) ?? 60,
      srcRoot: get('SRC', p.join(home, 'src')),
      defaultTarget: get('TARGET', p.join(home, 'src', 'cleanup-plate')),
      tickCmd: _words(get('TICK_CMD', 'paplay ${p.join(share, 'tick.wav')}')),
      fakeLlm: env['GAME_RESEARCH_FAKE_LLM'] ?? '',
      todoCmd: _words(
        get(
          'TODO_CMD',
          'dart run ${p.join(home, 'src', 'todo', 'bin', 'todo_note.dart')}',
        ),
      ),
      stillS: double.tryParse(get('STILL_S', '')) ?? 20,
      testMode: env['GAME_RESEARCH_TEST'] == '1',
      analyzeMode: get('ANALYZE', 'systemd'),
      claudeBin: get('CLAUDE', p.join(home, '.local', 'bin', 'claude')),
      omniUrl: get('OMNI_URL', 'http://127.0.0.1:20128'),
      omniModel: get('OMNI_MODEL', 'agnes/agnes-2.5-flash'),
      omniKeyFile: p.join(home, '.config', 'omniroute', 'api_key'),
      ollamaUrl: get('OLLAMA_URL', 'http://127.0.0.1:11434'),
      ollamaModel: get('OLLAMA_MODEL', 'qwen3-vl:30b-a3b-instruct'),
      i3Config: get('I3_CONFIG', p.join(home, '.config', 'i3', 'config')),
      flashPx: int.tryParse(get('FLASH_PX', '')) ?? 12,
      env: {
        for (final e in env.entries)
          if (e.key.startsWith('GAME_RESEARCH_')) e.key: e.value,
      },
    );
    if (config.testMode && config.display == ':0') {
      throw StateError('GAME_RESEARCH_TEST=1 refuses display :0');
    }
    return config;
  }

  const new _({
    required this.home,
    required this.repo,
    required this.port,
    required this.dataDir,
    required this.logFile,
    required this.autostartS,
    required this.defaultAppid,
    required this.windowTimeoutS,
    required this.relaunchS,
    required this.steamPidFile,
    required this.steamEnv,
    required this.xauthority,
    required this.procRoot,
    required this.steamRoot,
    required this.steamCmd,
    required this.display,
    required this.output,
    required this.audio,
    required this.fps,
    required this.srcRoot,
    required this.defaultTarget,
    required this.tickCmd,
    required this.fakeLlm,
    required this.todoCmd,
    required this.stillS,
    required this.testMode,
    required this.analyzeMode,
    required this.claudeBin,
    required this.omniUrl,
    required this.omniModel,
    required this.omniKeyFile,
    required this.ollamaUrl,
    required this.ollamaModel,
    required this.i3Config,
    required this.flashPx,
    required this.env,
  });

  /// `$HOME`.
  final String home;

  /// The checkout the app runs from (helpers/, build/).
  final String repo;

  /// Loopback port of the wrapper.
  final int port;

  /// Session folders: `<dataDir>/<stamp>-<game>/`.
  final String dataDir;

  /// The JSON-lines event log (every step, every failure).
  final String logFile;

  /// Seconds the autostart ring drains before the session starts.
  final double autostartS;

  /// Game started when none was used before (Librarian).
  final int defaultAppid;

  /// How long to wait for the game window after the launch, seconds.
  final double windowTimeoutS;

  /// Seconds between URI handoffs while Steam runs but the game does not
  /// (Steam finishes an update and does not launch afterwards).
  final double relaunchS;

  /// Steam's pid file; a live pid means the client runs.
  final String steamPidFile;

  /// Extra `K=V` for a Steam client PlayStudy starts (tests, Xvfb runs).
  final List<String> steamEnv;

  /// `$XAUTHORITY` handed to a Steam client PlayStudy starts ('' = none).
  final String xauthority;

  /// The proc filesystem (a temp dir in tests).
  final String procRoot;

  /// Steam's root (`steamapps/`, `appcache/librarycache/`).
  final String steamRoot;

  /// The `steam` command (a fake in the E2E).
  final String steamCmd;

  /// X display the game, hotkeys, dmenu and the flash live on.
  final String display;

  /// Output to record: '' = the monitor under the game window (default),
  /// a monitor name to prefer while it exists, or a fixed `WxH+X+Y`.
  final String output;

  /// Audio source: `default`, a `*.monitor`, or `lavfi` (tests).
  final String audio;

  /// Recording frame rate.
  final int fps;

  /// Folder whose children may be target projects.
  final String srcRoot;

  /// Target project when none was picked.
  final String defaultTarget;

  /// Tick command + args (the tag is appended); empty = no tick.
  final List<String> tickCmd;

  /// Executable replacing every model (tests): `<exe> <tier> <file>`.
  final String fakeLlm;

  /// The todo CLI command + args.
  final List<String> todoCmd;

  /// Shortest no-motion stretch reported, seconds.
  final double stillS;

  /// Test run: never display :0.
  final bool testMode;

  /// `systemd` (systemd-run --user job) or `inline` (a child process).
  final String analyzeMode;

  /// Absolute path of `claude` (it is a shell function in kuhy's zsh).
  final String claudeBin;

  /// OmniRoute gateway origin.
  final String omniUrl;

  /// Verified vision-capable free model (2026-11-11: red/blue test frame).
  final String omniModel;

  /// OmniRoute bearer key file; read at call time, never logged.
  final String omniKeyFile;

  /// ollama origin.
  final String ollamaUrl;

  /// ollama vision model.
  final String ollamaModel;

  /// i3 config checked for hotkey collisions.
  final String i3Config;

  /// Flash border thickness, pixels.
  final int flashPx;

  /// Every `GAME_RESEARCH_*` variable, passed on to the analysis job.
  final Map<String, String> env;
}

List<String> _words(String command) =>
    command.split(' ').where((w) => w.isNotEmpty).toList();
