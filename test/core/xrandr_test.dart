import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/xrandr.dart';

const _query = '''
Screen 0: minimum 8 x 8, current 6400 x 2160, maximum 32767 x 32767
HDMI-0 connected primary 2560x1440+3840+0 (normal left) 698mm x 393mm
DP-0 disconnected (normal left inverted right x axis y axis)
DP-1 connected (normal left inverted right x axis y axis)
DP-2 connected 3840x2160+0+0 (normal left inverted right) 620mm x 340mm
''';

void main() {
  test('parseXrandr lists connected outputs with a mode', () {
    final outs = parseXrandr(_query);
    expect(outs.map((o) => o.name), ['HDMI-0', 'DP-2']);
    expect(outs.first.primary, isTrue);
    expect(outs.first.x, 3840);
    expect(outs.last.width, 3840);
  });

  test('findOutput by name, null when absent (fail closed)', () {
    final outs = parseXrandr(_query);
    expect(findOutput(outs, 'DP-2')!.height, 2160);
    expect(findOutput(outs, 'DP-9'), isNull);
  });

  test('grab geometry: size and the display offset', () {
    final o = findOutput(parseXrandr(_query), 'HDMI-0')!;
    expect(o.videoSize, '2560x1440');
    expect(o.grabInput(':0'), ':0+3840,0');
  });

  test('parseGeometry reads WxH+X+Y, rejects junk', () {
    final o = parseGeometry('1280x720+0+0')!;
    expect(o.width, 1280);
    expect(o.name, 'geometry');
    expect(parseGeometry('1280x720'), isNull);
  });

  test('scaleFor: short side over 1080, nearest quarter, 1..3', () {
    expect(scaleFor(const Output(name: 'a', width: 3840, height: 2160)), 2);
    expect(scaleFor(const Output(name: 'b', width: 2560, height: 1440)), 1.25);
    expect(scaleFor(const Output(name: 'c', width: 1280, height: 800)), 1);
    expect(scaleFor(null), 1);
  });

  monitorTests();
}

// kuhy's real `xrandr --listmonitors` on :0 (2026-11-11): there is no DP-2.
const kuhyMonitors = '''
Monitors: 2
 0: +*DP-0 3840/620x2160/340+0+0  DP-0
 1: +HDMI-0 2560/698x1440/393+3840+0  HDMI-0
''';

void monitorTests() {
  test('parseMonitors reads names, rects and the primary star', () {
    final ms = parseMonitors(kuhyMonitors);
    expect(ms.map((m) => m.name), ['DP-0', 'HDMI-0']);
    expect(ms.first.primary, isTrue);
    expect(ms.last.geometry, '2560x1440+3840+0');
    expect(parseMonitors(' 0: screen 10/1x20/1+-5+7  none').single.x, -5);
  });

  test('pickOutput records the monitor the game window is on', () {
    final ms = parseMonitors(kuhyMonitors);
    const onHdmi = (x: 3900, y: 10, width: 1920, height: 1080);
    expect(pickOutput(ms, window: onHdmi)?.output.name, 'HDMI-0');
    expect(pickOutput(ms, window: onHdmi)?.why, 'window');
    // Straddling: the larger overlap wins.
    const straddle = (x: 3000, y: 0, width: 2000, height: 1000);
    expect(pickOutput(ms, window: straddle)?.output.name, 'HDMI-0');
  });

  test('pickOutput falls back to primary, then the first monitor', () {
    final ms = parseMonitors(kuhyMonitors);
    const offscreen = (x: -9000, y: 0, width: 100, height: 100);
    expect(pickOutput(ms, window: offscreen)?.output.name, 'DP-0');
    expect(pickOutput(ms)?.why, 'primary');
    final noPrimary = parseMonitors(' 0: +A 10/1x10/1+0+0  A\n');
    expect(pickOutput(noPrimary)?.why, 'first');
    expect(pickOutput(const []), isNull);
  });

  test('a pinned name wins when present, is ignored when missing', () {
    final ms = parseMonitors(kuhyMonitors);
    expect(pickOutput(ms, pin: 'HDMI-0')?.why, 'pinned');
    expect(pickOutput(ms, pin: 'DP-2')?.output.name, 'DP-0');
  });
}
