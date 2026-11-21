/// A fake steam-backlog-enforcer control socket: a unix server in a temp
/// dir that answers each request line from a script. Never the real one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The fake daemon.
class FakeEnforcer {
  new _(this.path, this._server);

  /// Binds a socket under [dir]; closed at test end.
  static Future<FakeEnforcer> start(Directory dir) async {
    final path = p.join(dir.path, 'ctl.sock');
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final fake = FakeEnforcer._(path, server);
    server.listen(fake._serve);
    addTearDown(server.close);
    return fake;
  }

  /// The socket path (`GAME_RESEARCH_ENFORCER_SOCK`).
  final String path;
  final ServerSocket _server;

  /// Requests seen: `{op, args}`.
  final requests = <Map<String, Object?>>[];

  /// Ops answered with an error.
  final refuse = <String>{};

  Future<void> _serve(Socket s) async {
    final line = await utf8.decoder
        .bind(s)
        .transform(const LineSplitter())
        .first;
    final req = jsonDecode(line) as Map<String, Object?>;
    requests.add(req);
    final reply = refuse.contains(req['op'])
        ? {'ok': false, 'error': 'invalid_params', 'message': 'no'}
        : {'ok': true, 'data': req['args']};
    s.write('${jsonEncode(reply)}\n');
    await s.flush();
    await s.close();
  }

  /// Op names seen, in order.
  List<Object?> get ops => [for (final r in requests) r['op']];

  /// Unused; keeps the analyzer quiet about [_server].
  int get port => _server.port;
}
