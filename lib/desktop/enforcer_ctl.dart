/// A client of the steam-backlog-enforcer control socket (one JSON line
/// out, one back, then the daemon closes). Only the research game ops use
/// it; the daemon admits root and the desktop user.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The daemon refused, failed or did not answer.
class EnforcerError implements Exception {
  /// Creates the error.
  const new(this.message);

  /// Why.
  final String message;

  @override
  String toString() => 'EnforcerError: $message';
}

/// The client over the socket at [path] ('' = no enforcer: every call fails).
class EnforcerCtl {
  /// Creates the client.
  const new(this.path, {this.timeout = const Duration(seconds: 10)});

  /// Socket path.
  final String path;

  /// Bound on connect and reply.
  final Duration timeout;

  /// Sends [op] with [args]; returns the reply's `data`.
  Future<Map<String, Object?>> call(
    String op, [
    Map<String, Object?> args = const {},
  ]) async {
    if (path.isEmpty) throw const EnforcerError('no enforcer socket');
    final String text;
    try {
      final s = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      ).timeout(timeout);
      s.write('${jsonEncode({'op': op, 'args': args})}\n');
      await s.flush();
      text = await utf8.decoder.bind(s).join().timeout(timeout);
      s.destroy();
    } on SocketException catch (e) {
      throw EnforcerError('socket $path: ${e.message}');
    } on TimeoutException {
      throw EnforcerError('socket $path: no answer');
    }
    final Object? reply;
    try {
      reply = jsonDecode(text.split('\n').first);
    } on FormatException {
      throw EnforcerError('socket $path: malformed reply');
    }
    if (reply is Map && reply['ok'] == true) {
      final data = reply['data'];
      return data is Map ? data.cast<String, Object?>() : const {};
    }
    final why = reply is Map ? '${reply['error']}: ${reply['message']}' : '';
    throw EnforcerError('$op refused $why'.trim());
  }
}
