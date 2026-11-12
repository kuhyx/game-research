import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/runner.dart';
import 'package:game_research/desktop/recording_flag.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

// kuhy (2026-11-11): the last session's analysis ran while he played the
// next one. The job waits while any recording runs, and resumes after.
void main() {
  late Fixture fx;
  late FakeSys fake;
  late RecordingFlag flag;
  void Function(Call)? onLlm;

  AnalysisRunner runner() => AnalysisRunner(
    fx.session.path,
    testConfig(
      fx.root,
      extra: {
        'GAME_RESEARCH_FAKE_LLM': '/fake/llm',
        'GAME_RESEARCH_TODO_CMD': 'faketodo',
        'GAME_RESEARCH_STILL_S': '2',
      },
    ),
    fake.sys,
    MockClient((_) async => throw StateError('no network in tests')),
    recordingPoll: const Duration(milliseconds: 5),
  );

  setUp(() {
    fx = Fixture();
    flag = RecordingFlag(p.join(fx.root.path, 'data'));
    onLlm = null;
    fake = FakeSys()
      ..onStart = ffmpegStart
      ..onRun = (c) {
        switch (c.exe) {
          case 'ffmpeg':
            return ffmpegFake(c);
          case '/fake/llm':
            onLlm?.call(c);
            return ok(c.args.first == 'opus' ? kAnswer : kCaptionJson);
          case 'faketodo':
            return ok('task-1');
        }
        return bad('no remote', 2);
      };
  });

  Future<void> idle() => Future<void>.delayed(const Duration(milliseconds: 60));

  test('the flag is live only while its pid runs', () {
    expect(flag.live, isFalse);
    flag.raise();
    expect(flag.file.readAsStringSync(), '$pid');
    expect(flag.live, isTrue);
    flag.file.writeAsStringSync('2147483000');
    expect(flag.live, isFalse, reason: 'a dead wrapper leaves no block');
    flag.file.writeAsStringSync('garbled');
    expect(flag.live, isFalse);
    flag
      ..lower()
      ..lower();
    expect(flag.file.existsSync(), isFalse);
  });

  test('analysis does not start while a recording runs', () async {
    flag.raise();
    var finished = false;
    final job = runner().run().then((code) {
      finished = true;
      return code;
    });
    await idle();
    expect(fake.calls, isEmpty, reason: 'no ffmpeg, no model while playing');
    expect(finished, isFalse);
    flag.lower();
    expect(await job, 0);
    expect(fake.of('ffmpeg'), isNotEmpty);
  });

  test('a running job pauses between items while a recording runs', () async {
    onLlm = (_) {
      if (fake.of('/fake/llm').length == 1) flag.raise();
    };
    final job = runner().run();
    await idle();
    expect(fake.of('/fake/llm'), hasLength(1), reason: 'paused after one');
    flag.lower();
    expect(await job, 0);
    expect(fake.of('/fake/llm').length, greaterThan(1));
  });
}
