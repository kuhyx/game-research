import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/desktop/session_parts.dart';

import '../support/fakes.dart';

void main() {
  test('real wires every service to the same config and seam', () {
    final config = testConfig(tempDir());
    final sys = FakeSys().sys;
    final parts = SessionParts.real(config, sys);
    expect(parts.config, same(config));
    expect(parts.sys, same(sys));
    expect(parts.recorder.config, same(config));
    expect(parts.hotkeys.unit, 'game-research-keys-18999');
    expect(parts.watcher.procRoot, '/proc');
    expect(parts.targets.current(), config.defaultTarget);
    expect(parts.store.config, same(config));
    expect(parts.analysis.config, same(config));
    expect(parts.overlay.config, same(config));
    expect(parts.asker.config, same(config));
    expect(parts.launcher.config, same(config));
  });
}
