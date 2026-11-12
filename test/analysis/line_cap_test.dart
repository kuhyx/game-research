import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/finish.dart';
import 'package:game_research/analysis/stage3.dart';
import 'package:game_research/core/doc_cap.dart';
import 'package:game_research/core/sampling.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:game_research/desktop/config.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';
import '../support/fakes.dart';

// kuhy, 2026-11-12: cleanup-plate caps .md at 250 lines and the template has
// 227. Code tidies Opus's answer, counts lines, asks once for a shorter one.
String _answer(int extraLines, {String blank = ''}) =>
    '$kDocMarker\n$kDraft${'x\n' * extraLines}$blank$kEndMarker\n';

const _frames = [SampleFrame(t: 12, kind: FrameKind.marker, file: 'f.png')];

void main() {
  late Fixture fx;
  late FakeSys fake;
  late List<String> answers;
  late List<String> prompts;

  Config cfg() => testConfig(
    fx.root,
    extra: {
      'GAME_RESEARCH_FAKE_LLM': '/fake/llm',
      'GAME_RESEARCH_TODO_CMD': 'faketodo',
    },
  );

  setUp(() {
    fx = Fixture();
    Directory(p.join(fx.session.path, 'analysis')).createSync();
    answers = [];
    prompts = [];
    fake = FakeSys()
      ..onRun = (c) {
        if (c.exe == '/fake/llm') {
          prompts.add(File(c.args.last).readAsStringSync());
          return ok(answers.removeAt(0));
        }
        return c.exe == 'faketodo'
            ? ok('t-1')
            : ok('git@github.com:kuhyx/cleanup-plate.git\n');
      };
  });

  Future<Map<String, Object?>> stage3() =>
      Stage3(fx.session.path, cfg(), fake.sys).run(fx.meta, _frames);

  String draft() =>
      File(draftPath(fx.target.path, 'alpha', '20261112-090025'))
          .readAsStringSync();

  group('stage 3', () {
    test('an answer within the cap costs one call', () async {
      answers = [_answer(100)];
      await stage3();
      expect(prompts, hasLength(1));
      expect(lineCount(draft()), lessThanOrEqualTo(kLineCap));
    });

    test('repeated blank lines are collapsed before counting', () async {
      // 120 x 3 blank lines would be 361 lines raw, 241 once collapsed.
      answers = ['$kDocMarker\n$kDraft${'x\n\n\n\n' * 60}$kEndMarker\n'];
      await stage3();
      expect(prompts, hasLength(1), reason: 'no shortening call needed');
      expect(draft(), isNot(contains('\n\n\n')));
    });

    test(
      'an overflow gets one shortening call, then the short draft',
      () async {
        answers = [_answer(300), _answer(150)];
        final state = await stage3();
        expect(prompts, hasLength(2));
        expect(prompts[1], contains('synthesis_long.txt'));
        expect(prompts[1], contains('at most $kShortenTo'));
        expect(prompts[1], contains('draft (30'));
        expect(
          fx.out('synthesis_long.txt').readAsStringSync(),
          contains('x\nx'),
        );
        expect(lineCount(draft()), lessThanOrEqualTo(kLineCap));
        expect(state['draft'], isNotNull);
      },
    );

    test('a second overflow fails closed and writes nothing', () async {
      answers = [_answer(300), _answer(280)];
      await expectLater(
        stage3(),
        throwsA(
          isA<StateError>().having(
            (e) => '$e',
            'message',
            allOf(contains('draft has 28'), contains('after one shortening')),
          ),
        ),
      );
      expect(prompts, hasLength(2), reason: 'never a third call');
      expect(
        File(draftPath(fx.target.path, 'alpha', '20261112-090025'))
            .existsSync(),
        isFalse,
      );
    });
  });

  group('finish', () {
    late String data;
    const report = '# Alpha report\nGood.\n';

    String sized(int mergedExtra, int reportExtra) => finishAnswer(
      merged: '$kDraft${'m\n' * mergedExtra}',
      report: '$report${'r\n' * reportExtra}',
    );

    Future<int> finish() => FinishRunner(
      'alpha',
      cfg(),
      fake.sys,
      recordingPoll: const Duration(milliseconds: 5),
    ).run();

    setUp(() {
      data = p.join(fx.root.path, 'data');
      final d = draftPath(fx.target.path, 'alpha', '20261112-090025');
      File(d)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(kDraft);
      File(p.join(fx.session.path, 'analysis', 'stage3.json'))
          .writeAsStringSync('{"draft": ${'"$d"'}}');
    });

    test('an overlong report is shortened once, both docs checked', () async {
      answers = [sized(10, 300), sized(10, 40)];
      expect(await finish(), 0);
      expect(prompts, hasLength(2));
      expect(prompts[1], contains('report (30'));
      expect(prompts[1], isNot(contains('merged answers (')));
      expect(
        lineCount(File(reportPath(fx.target.path, 'alpha')).readAsStringSync()),
        lessThanOrEqualTo(kLineCap),
      );
    });

    test('a second overflow fails the job with the reason', () async {
      answers = [sized(300, 0), sized(290, 0)];
      expect(await finish(), 1);
      final status = File(p.join(data, 'games', 'alpha', 'status.json'))
          .readAsStringSync();
      expect(status, contains('merged answers has 29'));
      expect(File(mergedPath(fx.target.path, 'alpha')).existsSync(), isFalse);
      expect(File(reportPath(fx.target.path, 'alpha')).existsSync(), isFalse);
    });
  });
}
