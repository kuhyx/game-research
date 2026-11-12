import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/launcher.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<String> get(int port, String path) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final res = await req.close();
    return await utf8.decoder.bind(res).join();
  } finally {
    client.close(force: true);
  }
}

void main() {
  late Directory root;
  late FakeSys fake;
  late List<String> errors;
  var holds = 0;

  Config configOn(int port, [Map<String, String> extra = const {}]) =>
      testConfig(
        root,
        extra: {
          'GAME_RESEARCH_PORT': '$port',
          'GAME_RESEARCH_REPO': root.path,
          ...extra,
        },
      );

  Future<int> run(
    List<String> args,
    Config config, {
    String browser = '/fake/chrome',
  }) => runDesktop(
    args,
    config,
    fake.sys,
    browserFinder: () => browser,
    hold: () async => holds++,
    err: errors.add,
  );

  setUpAll(() => HttpOverrides.global = null);

  setUp(() {
    root = tempDir();
    fake = FakeSys();
    errors = [];
    holds = 0;
    Directory(p.join(root.path, 'build', 'web')).createSync(recursive: true);
    File(p.join(root.path, 'build', 'web', 'index.html'))
        .writeAsStringSync('<html>page</html>');
  });

  test('the web root is build/web of the checkout', () {
    final config = configOn(1);
    expect(webRootOf(config), p.join(root.path, 'build', 'web'));
  });

  test('buildController wires the real parts to the seam', () {
    final controller = buildController(configOn(1), fake.sys);
    expect(controller.recording, isFalse);
    expect(controller.parts.sys, same(fake.sys));
  });

  test('serve releases stale keys and serves the page', () async {
    final config = configOn(0);
    final server = await serve(config, fake.sys, port: 0);
    addTearDown(server.close);
    expect(fake.calls.single.exe, 'systemctl');
    final port = await freePort();
    final second = await serve(config, fake.sys, port: port);
    addTearDown(second.close);
    expect(await get(port, '/'), '<html>page</html>');
  });

  test('--serve-only serves and holds without a window', () async {
    final port = await freePort();
    final code = await run(['--serve-only'], configOn(port));
    expect(code, 0);
    expect(holds, 1);
    expect(await get(port, '/api/state'), contains('"recording":false'));
    expect(fake.calls.where((c) => c.isStart), isEmpty);
  });

  test('--window-only opens the app window at the detected scale', () async {
    final port = await freePort();
    final config = configOn(port, {'GAME_RESEARCH_SCALE': '2'});
    final code = await run(['--window-only'], config);
    expect(code, 0);
    expect(holds, 0, reason: 'nothing served');
    final call = fake.calls.single;
    expect(call.exe, '/fake/chrome');
    expect(call.args.first, '--app=http://127.0.0.1:$port/?autostart=1');
    expect(call.args, contains('--force-device-scale-factor=2'));
    expect(call.args, contains('--mute-audio'));
    expect(call.env, {'DISPLAY': ':99'});
  });

  test('--no-autostart opens the window without the ring', () async {
    final port = await freePort();
    await run([
      '--window-only',
      '--no-autostart',
    ], configOn(port, {'GAME_RESEARCH_SCALE': '1'}));
    expect(fake.calls.single.args.first, '--app=http://127.0.0.1:$port/');
  });

  test('a control command goes to the CLI, not the wrapper', () async {
    final seen = <List<String>>[];
    final code = await runDesktop(
      ['--status'],
      configOn(1),
      fake.sys,
      cli: (args, _) async {
        seen.add(args);
        return 3;
      },
    );
    expect(
      [code, seen],
      [
        3,
        [
          ['--status'],
        ],
      ],
    );
    expect(fake.calls, isEmpty);
  });

  test('serve and window: the window ends, the server stays', () async {
    final port = await freePort();
    final code = await run([], configOn(port));
    expect(code, 0);
    expect(holds, 1);
    expect(fake.of('/fake/chrome'), hasLength(1));
    expect(await get(port, '/'), '<html>page</html>');
  });

  test('without a browser the server still serves', () async {
    final port = await freePort();
    final code = await run([], configOn(port), browser: '');
    expect(code, 0);
    expect(holds, 1);
    expect(errors.single, contains('no Chrome-family browser'));
    expect(fake.of('/fake/chrome'), isEmpty);
  });

  test('window-only without a browser is an error', () async {
    final code = await run(['--window-only'], configOn(1), browser: '');
    expect(code, 1);
    expect(holds, 0);
  });

  test('a port already taken only opens the window', () async {
    final busy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(busy.close);
    final code = await run([], configOn(busy.port));
    expect(code, 0);
    expect(errors.single, contains('already running on :${busy.port}'));
    expect(holds, 0);
    expect(fake.of('/fake/chrome'), hasLength(1));
  });

  test('serve-only on a taken port exits quietly', () async {
    final busy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(busy.close);
    final code = await runDesktop(
      ['--serve-only'],
      configOn(busy.port),
      fake.sys,
      hold: () async => holds++,
      err: errors.add,
    );
    expect(code, 0);
    expect(holds, 0);
    expect(errors, hasLength(1));
  });
}
