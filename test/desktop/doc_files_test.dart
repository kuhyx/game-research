import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/doc_files.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory root;
  late String target;
  late DocFiles docs;

  File put(String rel, [String text = '# t']) => File(p.join(target, rel))
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  setUp(() {
    root = tempDir();
    target = p.join(root.path, 'cleanup-plate');
    docs = DocFiles(() => [target]);
  });

  test('reads a markdown file under docs/research', () {
    final f = put('docs/research/games/g/DOCS-research-g-1.md', 'hello');
    expect(docs.read(f.path), 'hello');
  });

  test('write replaces an existing file', () {
    final f = put('docs/research/a.md');
    docs.write(f.path, 'new');
    expect(f.readAsStringSync(), 'new');
  });

  test('a path outside docs/research is refused', () {
    final other = put('docs/other.md');
    final outside = File(p.join(root.path, 'secret.md'))
      ..writeAsStringSync('s');
    for (final path in [other.path, outside.path, '/etc/passwd']) {
      expect(() => docs.read(path), throwsA(isA<DocDenied>()), reason: path);
      expect(() => docs.write(path, 'x'), throwsA(isA<DocDenied>()));
    }
    expect(other.readAsStringSync(), '# t');
  });

  test('.. traversal and sibling-prefix folders are refused', () {
    put('docs/research/ok.md');
    final secret = put('secret.md', 'secret');
    final viaDots = p.join(target, 'docs', 'research', '..', '..', 'secret.md');
    expect(() => docs.read(viaDots), throwsA(isA<DocDenied>()));
    expect(secret.readAsStringSync(), 'secret');
    final sibling = put('docs/research-evil/x.md');
    expect(() => docs.read(sibling.path), throwsA(isA<DocDenied>()));
    expect(() => docs.read('docs/research/ok.md'), throwsA(isA<DocDenied>()));
  });

  test('a symlink out of docs/research is refused', () {
    final secret = File(p.join(root.path, 'secret.md'))
      ..writeAsStringSync('secret');
    final dir = Directory(p.join(target, 'docs', 'research'))
      ..createSync(recursive: true);
    Link(p.join(dir.path, 'link.md')).createSync(secret.path);
    expect(
      () => docs.read(p.join(dir.path, 'link.md')),
      throwsA(isA<DocDenied>()),
    );
  });

  test('only .md files, only existing ones, only small ones', () {
    final txt = put('docs/research/a.txt');
    expect(() => docs.read(txt.path), throwsA(isA<DocDenied>()));
    final gone = p.join(target, 'docs', 'research', 'gone.md');
    expect(() => docs.read(gone), throwsA(isA<DocMissing>()));
    expect(() => docs.write(gone, 'x'), throwsA(isA<DocMissing>()));
    final big = put('docs/research/big.md');
    expect(
      () => docs.write(big.path, 'x' * (kDocMaxBytes + 1)),
      throwsA(isA<DocDenied>()),
    );
  });

  test('every target contributes its own root', () {
    final second = p.join(root.path, 'other');
    final f = File(p.join(second, 'docs', 'research', 'b.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync('b');
    expect(DocFiles(() => [target, second]).read(f.path), 'b');
    expect(() => docs.read(f.path), throwsA(isA<DocDenied>()));
  });
}
