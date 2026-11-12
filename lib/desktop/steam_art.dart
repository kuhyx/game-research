/// Game art from Steam's CDN, cached under `<data>/art`.
///
/// Used only for a game whose art Steam never cached locally. The network
/// call sits behind [ArtFetch] (tests pass a fake). A miss (CDN has neither
/// image, or the network is down) is remembered for a day in
/// `<appid>.miss` so a grid of tiles does not re-ask on every poll.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Fetches [url]; the bytes, or null on any failure (non-200, timeout).
typedef ArtFetch = Future<List<int>?> Function(Uri url);

const String _cdn =
    'https://shared.steamstatic.com/store_item_assets/steam/apps';

/// How long a miss is trusted.
const int kArtMissTtlS = 24 * 3600;

const int _maxBytes = 2 * 1024 * 1024;

/// A real [ArtFetch]: plain GET, 200 only, capped at 2 MiB, 6 s.
Future<List<int>?> httpArtFetch(Uri url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4)
    ..userAgent = 'game-research';
  try {
    final req = await client.getUrl(url);
    final res = await req.close().timeout(const Duration(seconds: 6));
    if (res.statusCode != HttpStatus.ok) {
      await res.drain<void>();
      return null;
    }
    final out = <int>[];
    await for (final chunk in res.timeout(const Duration(seconds: 6))) {
      out.addAll(chunk);
      if (out.length > _maxBytes) return null;
    }
    return out;
  } on Exception {
    return null;
  } finally {
    client.close(force: true);
  }
}

bool _isJpeg(List<int> b) =>
    b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

/// The download cache.
class SteamArt {
  /// Caches under [dir]; [now] is unix seconds.
  new({required this.dir, required this.fetch, double Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch / 1000);

  /// `<data>/art`.
  final String dir;

  /// The network seam.
  final ArtFetch fetch;
  final double Function() _now;
  final _inflight = <int, Future<File?>>{};

  File _file(int appid) => File(p.join(dir, '$appid.jpg'));
  File _miss(int appid) => File(p.join(dir, '$appid.miss'));

  /// The cached download of [appid], or null.
  File? cached(int appid) {
    final f = _file(appid);
    return f.existsSync() ? f : null;
  }

  /// Whether a recent attempt found nothing (retry after a day).
  bool missActive(int appid) {
    final f = _miss(appid);
    if (!f.existsSync()) return false;
    final until = double.tryParse(f.readAsStringSync().trim());
    return until != null && _now() < until;
  }

  /// The cached image, else a download (portrait, then header).
  Future<File?> get(int appid) async {
    final hit = cached(appid);
    if (hit != null) return hit;
    if (missActive(appid)) return null;
    final pending = _inflight[appid] ??= _download(appid);
    try {
      return await pending;
    } finally {
      // Removes a map entry; the Future it holds was awaited above.
      unawaited(_inflight.remove(appid));
    }
  }

  Future<File?> _download(int appid) async {
    for (final name in const ['library_600x900.jpg', 'header.jpg']) {
      final bytes = await fetch(Uri.parse('$_cdn/$appid/$name'));
      if (bytes == null || !_isJpeg(bytes)) continue;
      Directory(dir).createSync(recursive: true);
      return _file(appid)..writeAsBytesSync(bytes);
    }
    Directory(dir).createSync(recursive: true);
    _miss(appid).writeAsStringSync('${_now() + kArtMissTtlS}');
    return null;
  }
}
