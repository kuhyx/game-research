import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/ffmpeg_parse.dart';

void main() {
  test('parseSceneCuts reads showinfo pts_time values in order', () {
    const log = '''
[Parsed_showinfo_1 @ 0x5] n:   0 pts:  12800 pts_time:3.2 duration:256
[Parsed_showinfo_1 @ 0x5] n:   1 pts:  51200 pts_time:12.8   pos: 1
[Parsed_showinfo_1 @ 0x5] config in time_base: 1/1000
noise line
''';
    expect(parseSceneCuts(log), [3.2, 12.8]);
  });

  test('parseFreezes pairs start/end, an open freeze ends at duration', () {
    const log = '''
[freezedetect @ 0x1] lavfi.freezedetect.freeze_start: 4.5
[freezedetect @ 0x1] lavfi.freezedetect.freeze_duration: 21
[freezedetect @ 0x1] lavfi.freezedetect.freeze_end: 25.5
[freezedetect @ 0x1] lavfi.freezedetect.freeze_start: 40
''';
    final spans = parseFreezes(log, durationS: 70);
    expect(spans, hasLength(2));
    expect(spans[0].start, 4.5);
    expect(spans[0].end, 25.5);
    expect(spans[1].end, 70);
    expect(spans[1].length, 30);
    expect(spans[0].toJson(), {'start_s': 4.5, 'end_s': 25.5});
  });

  test('a dangling freeze_end without a start is ignored', () {
    const log = '[f] lavfi.freezedetect.freeze_end: 3\n';
    expect(parseFreezes(log, durationS: 10), isEmpty);
  });

  test('parseDuration reads ffprobe format duration, fails closed', () {
    expect(parseDuration('{"format":{"duration":"12.5"}}'), 12.5);
    expect(() => parseDuration('{"format":{}}'), throwsFormatException);
    expect(() => parseDuration('nope'), throwsFormatException);
  });

  test('parseChapterStarts reads ffprobe chapters in seconds', () {
    const json =
        '{"chapters":[{"start_time":"2.000000","tags":{"title":"good"}},'
        '{"start_time":"5.5","tags":{"title":"note: x"}}]}';
    final chapters = parseChapters(json);
    expect(chapters.map((c) => c.start), [2.0, 5.5]);
    expect(chapters.last.title, 'note: x');
    expect(parseChapters('{}'), isEmpty);
    expect(parseChapters('{"chapters":[{"start_time":"1"}]}').single.title, '');
  });
}
