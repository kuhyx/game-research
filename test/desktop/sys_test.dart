import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/sys.dart';

import '../support/fakes.dart';

void main() {
  test('unixNow is the wall clock in seconds', () {
    final before = DateTime.now().microsecondsSinceEpoch / 1e6;
    final now = unixNow();
    final after = DateTime.now().microsecondsSinceEpoch / 1e6;
    expect(now, inInclusiveRange(before, after));
  });

  test('the default seam reads the real clock', () {
    final now = const Sys().nowUnix();
    expect((now - unixNow()).abs(), lessThan(5));
  });

  test('a seam can swap every part', () async {
    final fake = FakeSys(now: 10, step: 2);
    final sys = fake.sys;
    expect(sys.nowUnix(), 10);
    expect(sys.nowUnix(), 12);
    final r = await sys.run('x', ['y'], environment: {'A': 'b'});
    expect(r.exitCode, 0);
    expect(fake.calls.single.line, 'x y');
    expect(fake.calls.single.env, {'A': 'b'});
  });
}
