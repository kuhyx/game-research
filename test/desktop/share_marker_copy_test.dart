import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/share_harness.dart';

const String _id = ShareHarness.id;

void main() {
  late ShareHarness x;

  setUp(() async => x = await ShareHarness.start());

  Future<int> status(String tail) async =>
      (await x.post('/api/sessions/$tail/copy')).status;

  test('copies the line of a marker and its still', () async {
    x.cutStills();
    final r = await x.post('/api/sessions/$_id/markers/1/copy');
    expect(r.json, {
      'ok': true,
      'files': 1,
      'chars': '👍 `0:01:05` nice'.length,
    });
    expect(x.starts.single.$2, '👍 `0:01:05` nice');
    expect(x.starts.single.$1, [
      p.join(x.session.path, 'analysis', 'clips', 'm_01_good.jpg'),
    ]);
  });

  test('404 without a still, session or marker', () async {
    expect(await status('$_id/markers/1'), 404);
    x.cutStills();
    expect(await status('$_id/markers/9'), 404);
    expect(await status('nope/markers/1'), 404);
    expect(await status('$_id/markers/x'), 404);
    expect(x.starts, isEmpty);
  });

  test('409 while a session records', () async {
    x.cutStills();
    await x.startRecording();
    expect(await status('$_id/markers/1'), 409);
    expect(x.starts, isEmpty);
  });
}
