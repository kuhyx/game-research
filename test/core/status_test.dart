import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/status.dart';
import 'package:game_research/core/usage.dart';

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

  test('tokens, cost, eta and start time round-trip', () {
    const s = AnalysisStatus(
      stage: 2,
      done: 3,
      total: 9,
      state: StageState.waiting,
      error: 'usage limit',
      tokens: Usage(
        input: 5,
        output: 6,
        cacheRead: 7,
        cacheWrite: 8,
        costUsd: 0.4,
      ),
      etaS: 12.5,
      startedUnix: 1700000000,
      retryUnix: 1700001800,
    );
    final json = s.toJson();
    expect(json['tokens'], {
      'in': 5,
      'out': 6,
      'cache_read': 7,
      'cache_write': 8,
    });
    expect(json['cost_usd'], 0.4);
    expect(json['eta_s'], 12.5);
    final back = AnalysisStatus.fromJson(json);
    expect(back.state, StageState.waiting);
    expect(back.tokens.cacheWrite, 8);
    expect(back.tokens.costUsd, 0.4);
    expect(back.etaS, 12.5);
    expect(back.startedUnix, 1700000000);
    expect(back.retryUnix, 1700001800);
    expect(_run(AnalysisStatus.idle).toJson()['eta_s'], isNull);
    expect(AnalysisStatus.fromJson(const {}).tokens.isEmpty, isTrue);
  });

  test('interrupted is a state of its own', () {
    expect(
      AnalysisStatus.fromJson(const {'state': 'interrupted'}).state,
      StageState.interrupted,
    );
  });

  test('the eta needs one finished item after the first report', () {
    final c = StageClock();
    expect(c.eta(100, 5, 10), isNull, reason: 'baseline');
    expect(c.eta(101, 5, 10), isNull, reason: 'nothing gained yet');
    expect(c.eta(110, 6, 10), 40);
    expect(c.eta(120, 7, 10), closeTo(20 * 3 / 2, 1e-9));
    expect(c.eta(100, 8, 10), isNull, reason: 'clock went backwards');
  });
}
