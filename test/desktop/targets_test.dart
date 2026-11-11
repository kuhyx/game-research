import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:game_research/desktop/targets.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory root;
  late Targets targets;
  late String src;
  late String fallback;

  String repo(String name) {
    final dir = p.join(src, name);
    final template = File(templatePaths(dir).en)
      ..createSync(recursive: true)
      ..writeAsStringSync('# q');
    expect(template.existsSync(), isTrue);
    return dir;
  }

  setUp(() {
    root = tempDir();
    final config = testConfig(root);
    targets = Targets(config);
    src = config.srcRoot;
    fallback = config.defaultTarget;
  });

  test('the default target is listed even without a source root', () {
    expect(targets.list(), [fallback]);
    expect(targets.current(), fallback);
  });

  test('folders with a questions template join, sorted, default first', () {
    final b = repo('zeta');
    final a = repo('alpha');
    Directory(p.join(src, 'plain')).createSync(recursive: true);
    File(p.join(src, 'file.txt')).writeAsStringSync('x');
    expect(targets.list(), [fallback, a, b]);
  });

  test('pick stores the target; an unknown one is refused', () {
    final a = repo('alpha');
    expect(targets.pick('/nope'), isFalse);
    expect(
      File(p.join(root.path, 'data', 'settings.json')).existsSync(),
      isFalse,
    );
    expect(targets.pick(a), isTrue);
    expect(targets.current(), a);
  });

  test('a vanished pick, a corrupt or odd settings file fall back', () {
    final a = repo('alpha');
    final settings = File(p.join(root.path, 'data', 'settings.json'));
    targets.pick(a);
    Directory(a).deleteSync(recursive: true);
    expect(targets.current(), fallback);
    settings.writeAsStringSync('{broken');
    expect(targets.current(), fallback);
    settings.writeAsStringSync('[1]');
    expect(targets.current(), fallback);
    settings.writeAsStringSync(jsonEncode({'target': 5}));
    expect(targets.current(), fallback);
  });

  test('toJson lists path and folder name and the current one', () {
    final a = repo('alpha');
    targets.pick(a);
    expect(targets.toJson(), {
      'current': a,
      'targets': [
        {'path': fallback, 'name': 'cleanup-plate'},
        {'path': a, 'name': 'alpha'},
      ],
    });
  });
}
