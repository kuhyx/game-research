import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/tiers.dart';
import 'package:game_research/desktop/config.dart';

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

String envelope(String result, {Object? usage, bool error = false}) =>
    jsonEncode({
      'type': 'result',
      'subtype': error ? 'error_during_execution' : 'success',
      'is_error': error,
      'result': result,
      'modelUsage': ?usage,
    });

void main() {
  late FakeSys fake;
  late Config config;

  ClaudeTier tier({int limitS = 180}) =>
      ClaudeTier(config, fake.sys, model: 'haiku', limitS: limitS);

  setUp(() {
    fake = FakeSys();
    config = testConfig(tempDir());
  });

  test('the tier is named after its model', () {
    expect(tier().name, 'haiku');
  });

  test('ask runs claude -p with Read only, in the first dir', () async {
    fake.onRun = (_) =>
        ok(envelope('answer', usage: {'claude-haiku-4-5': <String, Object>{}}));
    final r = await tier(limitS: 30).ask('the prompt', ['/a', '/b']);
    expect(r.error, isNull);
    expect(r.text, 'answer');
    expect(r.model, 'claude-haiku-4-5');
    final call = fake.calls.single;
    expect(call.exe, 'timeout');
    expect(call.args.take(3), ['30', config.claudeBin, '-p']);
    expect(call.args, contains('the prompt'));
    expect(call.args, containsAllInOrder(['--tools', 'Read']));
    expect(
      call.args,
      containsAllInOrder(['--add-dir', '/a', '--add-dir', '/b']),
    );
    expect(call.cwd, '/a');
  });

  test('a model-less envelope falls back to claude-<alias>', () async {
    fake.onRun = (_) => ok(envelope('x'));
    expect((await tier().ask('p', ['/a'])).model, 'claude-haiku');
  });

  test('a good envelope wins over a non-zero exit', () async {
    fake.onRun = (_) => ProcessResult(1, 1, envelope('late'), '');
    expect((await tier().ask('p', ['/a'])).text, 'late');
  });

  test('a failing exit with a bad envelope names the exit code', () async {
    fake.onRun = (_) => ProcessResult(1, 124, 'timed out', '');
    final r = await tier().ask('p', ['/a']);
    expect(r.error, startsWith('exit 124: no JSON envelope'));
  });

  test('exit 0 with an error envelope gives the clipped reason', () async {
    final long = 'x\n' * 200;
    fake.onRun = (_) => ok(envelope(long, error: true));
    final r = await tier().ask('p', ['/a']);
    expect(r.error, startsWith('claude error_during_execution: x x'));
    expect(r.error!.length, lessThanOrEqualTo(160));
    expect(r.error, isNot(contains('\n')));
  });

  test('a short reason is kept whole', () async {
    fake.onRun = (_) => ok(envelope('limit', error: true));
    expect(
      (await tier().ask('p', ['/a'])).error,
      'claude error_during_execution: limit',
    );
  });

  test('caption asks about the frame and reads its folder', () async {
    fake.onRun = (_) => ok(envelope(kCaptionJson));
    final r = await tier().caption('/frames/f_0001.png', 'describe');
    expect(r.text, kCaptionJson);
    final call = fake.calls.single;
    expect(call.args, contains(contains('/frames/f_0001.png')));
    expect(call.args, containsAllInOrder(['--add-dir', '/frames']));
  });
}
