import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/analysis/finish_sessions.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:path/path.dart' as p;

import '../support/analysis_fakes.dart';

void main() {
  late Fixture fx;
  late String data;

  setUp(() {
    fx = Fixture();
    data = p.join(fx.root.path, 'data');
  });

  test('v1 sessions with only draft_en count, deduplicated by path', () {
    final draft = draftPath(fx.target.path, 'alpha', '20261112-090025');
    File(draft)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(kDraft);
    File(p.join(fx.session.path, 'analysis', 'stage3.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'draft': draft}));
    final flat = File(p.join(fx.target.path, 'docs', 'research', 'DOCS-a.md'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(kDraft);
    for (final stamp in ['20261001-100000', '20261002-100000']) {
      final old = Directory(p.join(data, '$stamp-alpha'))
        ..createSync(recursive: true);
      File(p.join(old.path, 'session.json'))
          .writeAsStringSync(jsonEncode(fx.meta));
      File(p.join(old.path, 'analysis', 'stage3.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'draft_en': flat.path}));
    }
    final found = analysedSessions(data, 'alpha');
    expect(found.map((s) => s.draft), [flat.path, draft]);
    expect(found.first.stamp, '20261002-100000', reason: 'newest wins');
  });
}
