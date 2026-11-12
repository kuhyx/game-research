import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/claude_envelope.dart';
import 'package:game_research/core/usage.dart';

void main() {
  test('usage adds and round-trips with the status keys', () {
    const a = Usage(
      input: 1,
      output: 2,
      cacheRead: 3,
      cacheWrite: 4,
      costUsd: 0.5,
    );
    const b = Usage(input: 10, costUsd: 0.25);
    final sum = a + b;
    expect(sum.input, 11);
    expect(sum.costUsd, 0.75);
    expect(sum.tokens, {'in': 11, 'out': 2, 'cache_read': 3, 'cache_write': 4});
    expect(Usage.fromJson(sum.toJson()).output, 2);
    expect(Usage.fromJson(sum.toJson()).costUsd, 0.75);
    expect(Usage.fromJson(null).isEmpty, isTrue);
    expect(Usage.zero.isEmpty, isTrue);
    expect(a.isEmpty, isFalse);
  });

  test('claude usage block maps to the four counters and the cost', () {
    final u = Usage.fromClaude({
      'usage': {
        'input_tokens': 5,
        'output_tokens': 6,
        'cache_read_input_tokens': 7,
        'cache_creation_input_tokens': 8,
      },
      'total_cost_usd': 0.0123,
    });
    expect((u.input, u.output, u.cacheRead, u.cacheWrite), (5, 6, 7, 8));
    expect(u.costUsd, 0.0123);
    expect(Usage.fromClaude(const {}).isEmpty, isTrue);
  });

  test('openai and ollama usage', () {
    final o = Usage.fromOpenAi({
      'usage': {
        'prompt_tokens': 100,
        'completion_tokens': 20,
        'prompt_tokens_details': {'cached_tokens': 40},
      },
    });
    expect((o.input, o.output, o.cacheRead), (100, 20, 40));
    expect(Usage.fromOpenAi(const {'usage': 'x'}).isEmpty, isTrue);
    expect(
      Usage.fromOpenAi({
        'usage': {'prompt_tokens': 1},
      }).cacheRead,
      0,
    );
    final l = Usage.fromOllama({'prompt_eval_count': 9, 'eval_count': 3});
    expect((l.input, l.output), (9, 3));
  });

  test('the envelope carries its usage', () {
    final r = readClaudeEnvelope(
      '{"subtype":"success","is_error":false,"result":"x",'
      '"usage":{"input_tokens":2,"output_tokens":3},"total_cost_usd":0.5}',
    );
    expect(r.usage.input, 2);
    expect(r.usage.costUsd, 0.5);
    expect(
      readClaudeEnvelope('{"subtype":"success","result":"x"}').usage.isEmpty,
      isTrue,
    );
  });
}
