import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/cli.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/event_log.dart';

import '../support/fakes.dart';

void main() {
  late HttpServer server;
  late Config config;
  late List<String> seen;
  late List<String> printed;
  late List<String> phases;

  Future<int> cli(List<String> args) =>
      runCli(args, config, out: printed.add, sleep: (_) async {});

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    seen = [];
    printed = [];
    phases = ['idle'];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((req) async {
        seen.add('${req.method} ${req.uri}');
        final phase = phases.length > 1 ? phases.removeAt(0) : phases.single;
        req.response
          ..statusCode = req.uri.path == '/api/start' ? 409 : 200
          ..write(jsonEncode({'phase': phase}));
        await req.response.close();
      });
    config = testConfig(
      tempDir(),
      extra: {'GAME_RESEARCH_PORT': '${server.port}'},
    );
    addTearDown(() => server.close(force: true));
  });

  test('isCliCommand knows the control flags only', () {
    expect(isCliCommand(['--status']), isTrue);
    expect(isCliCommand(['--serve-only']), isFalse);
    expect(isCliCommand([]), isFalse);
  });

  test('each command hits its endpoint; non-2xx exits 1', () async {
    expect(await cli(['--status']), 0);
    expect(await cli(['--games']), 0);
    expect(await cli(['--sessions']), 0);
    expect(await cli(['--session', 'start', '--appid', '5']), 1);
    expect(await cli(['--session', 'start']), 1);
    expect(await cli(['--session', 'stop']), 0);
    expect(await cli(['--autostart', '--appid', '5']), 0);
    expect(await cli(['--cancel']), 0);
    expect(await cli(['--marker', 'good']), 0);
    expect(seen, [
      'GET /api/state',
      'GET /api/games',
      'GET /api/sessions',
      'POST /api/start?appid=5',
      'POST /api/start',
      'POST /api/stop',
      'POST /api/autostart?appid=5',
      'POST /api/autostart/cancel?src=cli',
      'POST /api/marker?tag=good',
    ]);
    expect(printed.first, '{"phase":"idle"}');
  });

  test('a bare --session is a usage error', () async {
    expect(await cli(['--session']), 2);
    expect(printed.single, contains('usage'));
  });

  test('--wait polls until the phase, or times out', () async {
    phases = ['idle', 'waiting', 'recording'];
    expect(await cli(['--wait', 'recording', '--timeout', '5']), 0);
    expect(seen, hasLength(3));
    phases = ['idle'];
    expect(await cli(['--wait', 'recording', '--timeout', '0.5']), 1);
    expect(printed.last, '{"phase":"idle"}');
  });

  test('--wait paces itself with a real pause by default', () async {
    phases = ['idle', 'armed'];
    final t = Stopwatch()..start();
    final code = await runCli(['--wait', 'armed'], config, out: printed.add);
    expect(code, 0);
    expect(t.elapsedMilliseconds, greaterThanOrEqualTo(450));
  });

  test('--log prints the last lines of the event log', () async {
    final log = EventLog(config.logFile);
    for (var i = 0; i < 3; i++) {
      log.event('e$i');
    }
    expect(await cli(['--log', '2']), 0);
    expect(printed.map((l) => (jsonDecode(l) as Map)['event']), ['e1', 'e2']);
    printed.clear();
    expect(await cli(['--log']), 0);
    expect(printed, hasLength(3));
  });

  test('no wrapper on the port exits 3', () async {
    await server.close(force: true);
    expect(await cli(['--status']), 3);
    expect(printed.single, contains('no wrapper'));
  });
}
