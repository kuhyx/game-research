import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled Inter so text measures with the real face (tests render
/// Ahem otherwise).
Future<void> loadInter() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<ByteData> asset(String name) => rootBundle.load('assets/fonts/$name');
  final upright = FontLoader('Inter')..addFont(asset('InterVariable.ttf'));
  await upright.load();
  final italic = FontLoader('Inter')
    ..addFont(asset('InterVariable-Italic.ttf'));
  await italic.load();
}

const _vocab = [
  'player',
  'item',
  'shelf',
  'cue',
  'plate',
  'sorting',
  'menu',
  'tutorial',
  'highlight',
  'outline',
  'slot',
  'drag',
  'snap',
  'feedback',
  'sound',
  'pace',
  'order',
  'basket',
  'counter',
  'timer',
  'hint',
  'label',
  'colour',
  'shape',
  'target',
  'reward',
  'pause',
  'level',
  'grid',
  'row',
  'stack',
  'tray',
  'reaches',
  'shows',
  'repeats',
  'ignores',
  'prefers',
  'delays',
  'confirms',
  'before',
  'after',
  'while',
  'when',
  'because',
  'never',
  'always',
  'often',
  'the',
  'a',
  'every',
  'each',
  'this',
  'that',
  'its',
  'one',
  'two',
  'first',
];

/// [n] deterministic words (no randomness, same text on every run).
String words(int seed, int n) {
  final out = <String>[];
  var x = seed * 7919 + 13;
  for (var i = 0; i < n; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    out.add(_vocab[(x >> 8) % _vocab.length]);
  }
  return out.join(' ');
}

/// Words of [text] (whitespace separated).
int wordCount(String text) =>
    text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// A finished report of about 800 words: H1, H2 sections, bullets with refs.
String reportFixture() {
  final b = StringBuffer('# Research report: Sample Game\n\n')
    ..writeln('Session: 20261101-120000, 62 captioned frames.');
  var seed = 1;
  for (var s = 1; s <= 5; s++) {
    b.writeln('\n## $s. ${words(seed++, 3)}\n');
    for (var i = 0; i < 4; i++) {
      final f = (s * 10 + i).toString().padLeft(4, '0');
      b.writeln('- ${words(seed++, 33)} (f_$f, 0$s:1$i)');
    }
  }
  return b.toString();
}

/// A draft of about 3,500 words in the real structure: questions with
/// Answer / Status / Evidence / For lines, every fourth one still open.
String draftFixture() {
  final b = StringBuffer('# Research questions: Sample Game\n\n')
    ..writeln('<!-- game-research template v1 -->\n')
    ..writeln('Session: 20261101-120000');
  var seed = 100;
  for (var s = 1; s <= 4; s++) {
    b.writeln('\n## $s. ${words(seed++, 3)}');
    for (var q = 1; q <= 8; q++) {
      final status = switch (q % 4) {
        0 => 'open',
        2 => 'partial',
        _ => 'answered',
      };
      final open = status == 'open';
      final answer = open ? '_(pending)_' : words(seed++, 50);
      final evidence = open
          ? '_(pending)_'
          : '${words(seed++, 26)} (f_${s * 100 + q}, 0$q:2$s)';
      final forRepo = open ? '_(pending)_' : words(seed++, 24);
      b
        ..writeln('\n### Q$s.$q ${words(seed++, 7)}?')
        ..writeln('Why we ask: ${words(seed++, 12)}')
        ..writeln('- **Answer:** $answer')
        ..writeln('- **Status:** $status')
        ..writeln('- **Evidence:** $evidence')
        ..writeln('- **For cleanup-plate:** $forRepo');
    }
  }
  b.writeln('\n## Open threads\n\n_(pending)_');
  return b.toString();
}
