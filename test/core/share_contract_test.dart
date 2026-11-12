import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/markers.dart';
import 'package:game_research/core/share_contract.dart';

void main() {
  test('stillName: 2-digit 1-based index, tag, jpg', () {
    expect(stillName(1, MarkerTag.good), 'm_01_good.jpg');
    expect(stillName(12, MarkerTag.confusing), 'm_12_confusing.jpg');
    expect(stillName(103, MarkerTag.note), 'm_103_note.jpg');
  });

  test('stillName matches the clip numbering of stage 1', () {
    // Stage 1 cuts `m_NN_<tag>.mkv`; the still shares the stem.
    expect(stillName(3, MarkerTag.bad).replaceAll('.jpg', ''), 'm_03_bad');
  });

  test('stillArgv: one full-resolution frame at the offset, quality 2', () {
    expect(stillArgv('/d/recording.mkv', 12.3456, '/d/out.jpg'), [
      '-hide_banner',
      '-nostdin',
      '-v',
      'error',
      '-seek_timestamp',
      '1',
      '-ss',
      '12.346',
      '-i',
      '/d/recording.mkv',
      '-frames:v',
      '1',
      '-q:v',
      '2',
      '-y',
      '/d/out.jpg',
    ]);
    expect(stillArgv('v', 0, 'o').contains('scale'), isFalse);
  });

  test('hms: h:mm:ss, seconds floored', () {
    expect(hms(0), '0:00:00');
    expect(hms(59.99), '0:00:59');
    expect(hms(61), '0:01:01');
    expect(hms(3599.5), '0:59:59');
    expect(hms(3600), '1:00:00');
    expect(hms(37230), '10:20:30');
    expect(hms(-4), '0:00:00');
  });

  test('every tag has its emoji', () {
    expect(
      {for (final t in MarkerTag.values) t.name: tagEmoji(t)},
      {'good': '👍', 'bad': '👎', 'confusing': '❓', 'note': '📝'},
    );
  });
}
