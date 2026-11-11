import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/status.dart';

AnalysisStatus _run(AnalysisStatus Function() make) => make();

void main() {
  test('progress spans the three stages', () {
    // A tear-off, so the constructor runs at runtime (const folds away).
    expect(_run(AnalysisStatus.idle).progress, 0);
    expect(
      const AnalysisStatus(
        stage: 2,
        done: 5,
        total: 10,
        state: StageState.running,
      ).progress,
      closeTo(0.5, 1e-9),
    );
    expect(
      const AnalysisStatus(
        stage: 3,
        done: 1,
        total: 1,
        state: StageState.done,
      ).progress,
      1,
    );
    expect(
      const AnalysisStatus(
        stage: 1,
        done: 0,
        total: 0,
        state: StageState.running,
      ).progress,
      0,
    );
  });

  test('round-trips through json; unknown state reads as idle', () {
    const s = AnalysisStatus(
      stage: 2,
      done: 3,
      total: 4,
      state: StageState.failed,
      error: 'every tier failed on f_0002.png',
    );
    final back = AnalysisStatus.fromJson(s.toJson());
    expect(back.state, StageState.failed);
    expect(back.error, contains('f_0002'));
    expect(back.total, 4);
    expect(
      AnalysisStatus.fromJson(const {'state': 'weird'}).state,
      StageState.idle,
    );
  });
}
