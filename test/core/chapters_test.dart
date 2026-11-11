import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/chapters.dart';
import 'package:game_research/core/markers.dart';

Marker _m(double t, MarkerTag tag, [String note = '']) =>
    Marker(wallUnix: 100 + t, offsetS: t, tag: tag, note: note);

void main() {
  test('no markers gives a header and no chapter', () {
    final text = chaptersFfmetadata(const [], 30);
    expect(text, startsWith(';FFMETADATA1\n'));
    expect(text, isNot(contains('[CHAPTER]')));
  });

  test('each marker opens a chapter that runs to the next one', () {
    final text = chaptersFfmetadata([
      _m(2, MarkerTag.good),
      _m(5.5, MarkerTag.note, 'what is this'),
    ], 10);
    final chapters = text.split('[CHAPTER]').skip(1).toList();
    expect(chapters, hasLength(2));
    expect(chapters[0], contains('TIMEBASE=1/1000'));
    expect(chapters[0], contains('START=2000'));
    expect(chapters[0], contains('END=5500'));
    expect(chapters[0], contains('title=good'));
    expect(chapters[1], contains('START=5500'));
    expect(chapters[1], contains('END=10000'));
    expect(chapters[1], contains('title=note: what is this'));
  });

  test('markers out of order are sorted first', () {
    final text = chaptersFfmetadata([
      _m(6, MarkerTag.bad),
      _m(1, MarkerTag.good),
    ], 8);
    expect(text.indexOf('title=good'), lessThan(text.indexOf('title=bad')));
  });

  test('a marker at or past the end still gets a 1 ms chapter', () {
    final text = chaptersFfmetadata([_m(12, MarkerTag.confusing)], 10);
    expect(text, contains('START=10000'));
    expect(text, contains('END=10001'));
  });

  test('two markers at the same instant do not make an empty chapter', () {
    final text = chaptersFfmetadata([
      _m(3, MarkerTag.good),
      _m(3, MarkerTag.bad),
    ], 10);
    expect(text, contains('START=3000\nEND=3001'));
    expect(text, contains('START=3001\nEND=10000'));
  });

  test('metadata specials in a note are escaped', () {
    expect(escapeMetadata(r'a=b;c#d\e'), r'a\=b\;c\#d\\e');
    expect(
      escapeMetadata('two\nlines'),
      r'two\'
      '\nlines',
    );
  });
}
