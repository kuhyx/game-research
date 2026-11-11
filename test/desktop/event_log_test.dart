import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/event_log.dart';
import 'package:game_research/desktop/settings_file.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

void main() {
  late Directory root;

  setUp(() => root = tempDir());

  test('events append as JSON lines with a time stamp', () {
    final log = EventLog(p.join(root.path, 'logs', 'x.jsonl'), clock: () => 5);
    expect(log.tail(3), isEmpty);
    log
      ..event('a')
      ..event('b', {'n': 1})
      ..event('c');
    expect(log.tail(2).map(jsonDecode), [
      {'t': 5, 'event': 'b', 'n': 1},
      {'t': 5, 'event': 'c'},
    ]);
    expect(log.tail(9), hasLength(3));
  });

  test('an unwritable log does not throw', () {
    final file = File(p.join(root.path, 'file'))..writeAsStringSync('');
    EventLog(p.join(file.path, 'under-a-file.jsonl')).event('lost');
  });

  test('settings: missing, corrupt and non-object files read as {}', () {
    final s = SettingsFile(p.join(root.path, 'd', 'settings.json'));
    expect(s.read(), isEmpty);
    s
      ..merge({'target': '/t'})
      ..merge({'last_appid': 4});
    expect(s.read(), {'target': '/t', 'last_appid': 4});
    File(s.path).writeAsStringSync('{bad');
    expect(s.read(), isEmpty);
    File(s.path).writeAsStringSync('[1]');
    expect(s.read(), isEmpty);
  });
}
