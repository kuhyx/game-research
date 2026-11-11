/// The control CLI: drive and inspect a running wrapper without the GUI.
///
///     --status                      /api/state (phase, pending, error)
///     --games | --sessions          the picker list | past sessions
///     --session start [--appid N]   launch (default: the last game)
///     --session stop                stop recording or cancel a pending start
///     --autostart [--appid N]       arm the autostart ring
///     --cancel                      cancel the ring or a pending launch
///     --marker good|bad|confusing|note
///     --log [N]                     last N event-log lines (default 50)
///     --wait PHASE [--timeout S]    poll until phase == PHASE (default 60 s)
///
/// Prints JSON; exit 0 = 2xx, 1 = refused or timed out, 2 = usage, 3 = no
/// wrapper on the port. The port is `GAME_RESEARCH_PORT` (default 8805).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/event_log.dart';

const _commands = {
  '--status',
  '--games',
  '--sessions',
  '--session',
  '--autostart',
  '--cancel',
  '--marker',
  '--log',
  '--wait',
};

/// Whether [args] name a control command rather than the wrapper itself.
bool isCliCommand(List<String> args) => args.any(_commands.contains);

String? _after(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

/// Runs one command against the wrapper on [Config.port]; [out] gets the
/// JSON, [sleep] paces `--wait`.
Future<int> runCli(
  List<String> args,
  Config config, {
  void Function(String) out = print,
  Future<void> Function(Duration) sleep = _sleep,
}) async {
  final appid = _after(args, '--appid');
  final q = appid == null ? '' : '?appid=$appid';
  if (args.contains('--log')) {
    final n = int.tryParse(_after(args, '--log') ?? '') ?? 50;
    EventLog(config.logFile).tail(n).forEach(out);
    return 0;
  }
  final client = HttpClient();
  Future<int> call(String method, String path) =>
      _call(client, method, 'http://127.0.0.1:${config.port}$path', out);
  try {
    if (args.contains('--status')) return await call('GET', '/api/state');
    if (args.contains('--games')) return await call('GET', '/api/games');
    if (args.contains('--sessions')) return await call('GET', '/api/sessions');
    if (args.contains('--cancel')) {
      return await call('POST', '/api/autostart/cancel?src=cli');
    }
    if (args.contains('--autostart')) {
      return await call('POST', '/api/autostart$q');
    }
    final marker = _after(args, '--marker');
    if (marker != null) return await call('POST', '/api/marker?tag=$marker');
    final phase = _after(args, '--wait');
    if (phase != null) {
      final limit = double.tryParse(_after(args, '--timeout') ?? '') ?? 60;
      return await _wait(client, config.port, phase, limit, out, sleep);
    }
    return switch (_after(args, '--session')) {
      'start' => await call('POST', '/api/start$q'),
      'stop' => await call('POST', '/api/stop'),
      _ => _usage(out),
    };
  } on SocketException {
    out(jsonEncode({'error': 'no wrapper on :${config.port}'}));
    return 3;
  } finally {
    client.close(force: true);
  }
}

int _usage(void Function(String) out) {
  out(jsonEncode({'error': 'usage: see lib/desktop/cli.dart'}));
  return 2;
}

Future<int> _call(
  HttpClient client,
  String method,
  String url,
  void Function(String) out,
) async {
  final req = await client.openUrl(method, Uri.parse(url));
  final res = await req.close();
  final body = await utf8.decoder.bind(res).join();
  out(body);
  return res.statusCode < 300 ? 0 : 1;
}

Future<int> _wait(
  HttpClient client,
  int port,
  String phase,
  double limitS,
  void Function(String) out,
  Future<void> Function(Duration) sleep,
) async {
  final url = Uri.parse('http://127.0.0.1:$port/api/state');
  final steps = (limitS * 2).ceil();
  var last = '';
  for (var i = 0; i <= steps; i++) {
    final res = await (await client.getUrl(url)).close();
    last = await utf8.decoder.bind(res).join();
    final state = jsonDecode(last) as Map<String, Object?>;
    if (state['phase'] == phase) {
      out(last);
      return 0;
    }
    if (i < steps) await sleep(const Duration(milliseconds: 500));
  }
  out(last);
  return 1;
}

Future<void> _sleep(Duration d) => Future<void>.delayed(d);
