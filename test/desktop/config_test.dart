import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/config.dart';

Config load(Map<String, String> env) => Config.fromEnv(env, cwd: '/repo');

void main() {
  test('defaults come from HOME and the cwd', () {
    final c = load({'HOME': '/h', 'DISPLAY': ':7'});
    expect(c.home, '/h');
    expect(c.repo, '/repo');
    expect(c.port, kDefaultPort);
    expect(c.dataDir, '/h/data/game-research');
    expect(c.steamRoot, '/h/.local/share/Steam');
    expect(c.steamCmd, 'steam');
    expect(c.display, ':7');
    expect(c.output, '', reason: 'auto: the game window decides');
    expect(c.audio, 'default');
    expect(c.fps, 60);
    expect(c.srcRoot, '/h/src');
    expect(c.defaultTarget, '/h/src/cleanup-plate');
    expect(c.tickCmd, ['paplay', '/h/.local/share/game-research/tick.wav']);
    expect(c.todoCmd, ['dart', 'run', '/h/src/todo/bin/todo_note.dart']);
    expect(c.fakeLlm, '');
    expect(c.stillS, 20);
    expect(c.testMode, isFalse);
    expect(c.analyzeMode, 'systemd');
    expect(c.claudeBin, '/h/.local/bin/claude');
    expect(c.omniUrl, 'http://127.0.0.1:20128');
    expect(c.omniModel, 'agnes/agnes-2.5-flash');
    expect(c.omniKeyFile, '/h/.config/omniroute/api_key');
    expect(c.ollamaUrl, 'http://127.0.0.1:11434');
    expect(c.ollamaModel, 'qwen3-vl:30b-a3b-instruct');
    expect(c.i3Config, '/h/.config/i3/config');
    expect(c.flashPx, 12);
    expect(c.env, isEmpty);
  });

  test('no HOME and no DISPLAY fall back to / and :0', () {
    final c = load({});
    expect(c.home, '/');
    expect(c.display, ':0');
  });

  test('every GAME_RESEARCH_ variable overrides its default', () {
    final c = load({
      'HOME': '/h',
      'GAME_RESEARCH_REPO': '/r',
      'GAME_RESEARCH_PORT': '9001',
      'GAME_RESEARCH_DATA': '/d',
      'GAME_RESEARCH_STEAM_ROOT': '/s',
      'GAME_RESEARCH_STEAM_CMD': 'fakesteam',
      'GAME_RESEARCH_DISPLAY': ':99',
      'GAME_RESEARCH_OUTPUT': '800x600+0+0',
      'GAME_RESEARCH_AUDIO': 'lavfi',
      'GAME_RESEARCH_FPS': '30',
      'GAME_RESEARCH_SRC': '/src',
      'GAME_RESEARCH_TARGET': '/t',
      'GAME_RESEARCH_TICK_CMD': 'play  -q',
      'GAME_RESEARCH_FAKE_LLM': '/fake',
      'GAME_RESEARCH_TODO_CMD': 'todo --x',
      'GAME_RESEARCH_STILL_S': '2.5',
      'GAME_RESEARCH_ANALYZE': 'inline',
      'GAME_RESEARCH_CLAUDE': '/c',
      'GAME_RESEARCH_OMNI_URL': 'http://o',
      'GAME_RESEARCH_OMNI_MODEL': 'om',
      'GAME_RESEARCH_OLLAMA_URL': 'http://l',
      'GAME_RESEARCH_OLLAMA_MODEL': 'lm',
      'GAME_RESEARCH_I3_CONFIG': '/i3',
      'GAME_RESEARCH_FLASH_PX': '3',
      'UNRELATED': 'x',
    });
    expect(c.repo, '/r');
    expect(c.port, 9001);
    expect(c.dataDir, '/d');
    expect(c.steamRoot, '/s');
    expect(c.steamCmd, 'fakesteam');
    expect(c.display, ':99');
    expect(c.output, '800x600+0+0');
    expect(c.audio, 'lavfi');
    expect(c.fps, 30);
    expect(c.srcRoot, '/src');
    expect(c.defaultTarget, '/t');
    expect(c.tickCmd, ['play', '-q']);
    expect(c.fakeLlm, '/fake');
    expect(c.todoCmd, ['todo', '--x']);
    expect(c.stillS, 2.5);
    expect(c.analyzeMode, 'inline');
    expect(c.claudeBin, '/c');
    expect(c.omniUrl, 'http://o');
    expect(c.omniModel, 'om');
    expect(c.ollamaUrl, 'http://l');
    expect(c.ollamaModel, 'lm');
    expect(c.i3Config, '/i3');
    expect(c.flashPx, 3);
    expect(c.env.keys, everyElement(startsWith('GAME_RESEARCH_')));
    expect(c.env, isNot(contains('UNRELATED')));
  });

  test('empty or unparsable values fall back', () {
    final c = load({
      'HOME': '/h',
      'GAME_RESEARCH_PORT': 'abc',
      'GAME_RESEARCH_FPS': '',
      'GAME_RESEARCH_STILL_S': 'x',
      'GAME_RESEARCH_FLASH_PX': 'y',
    });
    expect(c.port, kDefaultPort);
    expect(c.fps, 60);
    expect(c.stillS, 20);
    expect(c.flashPx, 12);
  });

  test('test mode refuses display :0 but takes a private one', () {
    expect(() => load({'GAME_RESEARCH_TEST': '1'}), throwsA(isA<StateError>()));
    expect(
      () => load({'GAME_RESEARCH_TEST': '1', 'GAME_RESEARCH_DISPLAY': ':0'}),
      throwsA(isA<StateError>()),
    );
    final c = load({'GAME_RESEARCH_TEST': '1', 'GAME_RESEARCH_DISPLAY': ':42'});
    expect(c.testMode, isTrue);
    expect(c.display, ':42');
  });
}
