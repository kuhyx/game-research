import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/claude_envelope.dart';

void main() {
  test('a success envelope gives its result text', () {
    final r = readClaudeEnvelope(
      '{"type":"result","subtype":"success","is_error":false,'
      '"result":"hello"}',
    );
    expect(r.ok, isTrue);
    expect(r.text, 'hello');
    expect(r.model, isNull);
  });

  test('the answering model comes from modelUsage', () {
    final r = readClaudeEnvelope(
      '{"subtype":"success","is_error":false,"result":"x",'
      '"modelUsage":{"claude-haiku-4-5":{"inputTokens":1}}}',
    );
    expect(r.model, 'claude-haiku-4-5');
  });

  test('is_error, a non-success subtype or no result fail', () {
    expect(
      readClaudeEnvelope(
        '{"subtype":"success","is_error":true,"result":"limit"}',
      ).ok,
      isFalse,
    );
    expect(
      readClaudeEnvelope('{"subtype":"error_max_turns","result":"x"}').ok,
      isFalse,
    );
    expect(readClaudeEnvelope('{"subtype":"success"}').ok, isFalse);
  });

  test('garbage or a non-object fails with the reason', () {
    final r = readClaudeEnvelope('Claude AI usage limit reached');
    expect(r.ok, isFalse);
    expect(r.reason, contains('usage limit'));
    expect(readClaudeEnvelope('[1]').ok, isFalse);
  });

  test('a stream of lines uses the last result line', () {
    final r = readClaudeEnvelope(
      '{"type":"system"}\n'
      '{"type":"result","subtype":"success","is_error":false,"result":"b"}\n',
    );
    expect(r.text, 'b');
  });
}
