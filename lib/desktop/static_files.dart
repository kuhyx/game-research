/// Serving the Flutter web build from disk.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Content type for [filePath]. CanvasKit refuses a `.wasm` served as
/// anything but `application/wasm`, and the app then renders nothing.
ContentType contentTypeFor(String filePath) =>
    switch (p.extension(filePath).toLowerCase()) {
      '.html' => ContentType.html,
      '.js' || '.mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      '.json' => ContentType.json,
      '.wasm' => ContentType('application', 'wasm'),
      '.css' => ContentType('text', 'css', charset: 'utf-8'),
      '.png' => ContentType('image', 'png'),
      '.svg' => ContentType('image', 'svg+xml'),
      '.ttf' => ContentType('font', 'ttf'),
      '.otf' => ContentType('font', 'otf'),
      _ => ContentType.binary,
    };

/// Writes [segments] of [webRoot] to [res]; index.html for `/`, 403 for a
/// path that escapes the root, 404 for a missing file.
Future<void> serveStatic(
  HttpResponse res,
  String webRoot,
  List<String> segments,
) async {
  final relative = segments.isEmpty ? ['index.html'] : segments;
  final resolved = p.normalize(p.joinAll([webRoot, ...relative]));
  if (!p.isWithin(webRoot, resolved)) {
    res.statusCode = HttpStatus.forbidden;
    return;
  }
  final file = File(resolved);
  if (!file.existsSync()) {
    res.statusCode = HttpStatus.notFound;
    return;
  }
  res.headers.contentType = contentTypeFor(resolved);
  await res.addStream(file.openRead());
}
