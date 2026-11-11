import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/static_files.dart';

void main() {
  test('content types by extension, wasm exactly application/wasm', () {
    String mime(String f) => contentTypeFor(f).mimeType;
    expect(mime('a/index.HTML'), 'text/html');
    expect(mime('main.dart.js'), 'text/javascript');
    expect(mime('x.mjs'), 'text/javascript');
    expect(mime('manifest.json'), 'application/json');
    expect(mime('canvaskit.wasm'), 'application/wasm');
    expect(mime('a.css'), 'text/css');
    expect(mime('a.png'), 'image/png');
    expect(mime('a.svg'), 'image/svg+xml');
    expect(mime('a.ttf'), 'font/ttf');
    expect(mime('a.otf'), 'font/otf');
    expect(mime('a.bin'), 'application/octet-stream');
    expect(contentTypeFor('a.js').charset, 'utf-8');
  });
}
