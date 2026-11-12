import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/hotkeys.dart';

void main() {
  final cfg = sxhkdConfig(port: 8791, curl: '/usr/bin/curl');

  test('binds Mod+F1..F4 to the four markers and Mod+Shift+F4 to stop', () {
    expect(cfg, contains('super + F1\n'));
    expect(cfg, contains('super + F2\n'));
    expect(cfg, contains('super + F3\n'));
    expect(cfg, contains('super + F4\n'));
    expect(cfg, contains('super + shift + F4\n'));
    expect(cfg, contains('/api/marker?tag=good&src=key&ask=1'));
    expect(cfg, contains('/api/marker?tag=bad&src=key&ask=1'));
    expect(cfg, contains('/api/marker?tag=confusing&src=key&ask=1'));
    expect(cfg, contains('/api/marker?tag=note&src=key&ask=1'));
    expect(cfg, contains('/api/stop'));
  });

  test('every command posts to loopback on the given port', () {
    final commands = cfg.split('\n').where((l) => l.startsWith('\t'));
    expect(commands, hasLength(5));
    for (final c in commands) {
      expect(c, contains("-X POST 'http://127.0.0.1:8791/"));
      expect(c, startsWith('\t/usr/bin/curl -fsS -m 3'));
    }
  });

  test('the bound keys are listed for the collision check', () {
    expect(kHotkeys.map((h) => h.chord), [
      'super + F1',
      'super + F2',
      'super + F3',
      'super + F4',
      'super + shift + F4',
    ]);
  });

  test('i3Collisions finds a bindsym on one of our chords', () {
    const i3 = r'''
set $mod Mod4
bindsym $mod+d exec dmenu_run
bindsym $mod+F2 exec firefox
bindsym Mod4+Shift+F4 kill
# bindsym $mod+F1 exec commented
bindcode $mod+67 exec x
''';
    expect(i3Collisions(i3), [
      'super + F2',
      'super + shift + F4',
      'super + F1',
    ]);
    expect(i3Collisions('bindsym \$mod+F5 exec x\n'), isEmpty);
  });

  shortcutTests();
}

void shortcutTests() {
  test('shortcutFor reads the key legend from the generated bindings', () {
    expect(shortcutFor('good'), 'Super+F1');
    expect(shortcutFor('bad'), 'Super+F2');
    expect(shortcutFor('confusing'), 'Super+F3');
    expect(shortcutFor('note'), 'Super+F4');
    expect(shortcutFor('stop'), 'Super+Shift+F4');
    expect(shortcutFor('start'), isNull);
    for (final k in kHotkeys) {
      // The label is the very chord sxhkd gets, only re-spelt.
      final label = keyLegend(k.chord).toLowerCase().replaceAll('+', ' + ');
      expect(label, k.chord.toLowerCase());
    }
  });
}
