/// Token usage and cost of model calls, as recorded in `captions.jsonl` rows,
/// `stage3.json`, `finish.json` and `status.json`.
library;

/// Tokens and dollars spent by one or more model calls.
class Usage {
  /// Creates a usage; every counter defaults to 0.
  const new({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
    this.costUsd = 0,
  });

  /// Reads a usage object written by [toJson]; null or junk reads as zero.
  factory fromJson(Object? json) {
    if (json is! Map) return zero;
    int n(String k) => (json[k] as num?)?.toInt() ?? 0;
    return Usage(
      input: n('in'),
      output: n('out'),
      cacheRead: n('cache_read'),
      cacheWrite: n('cache_write'),
      costUsd: (json['cost_usd'] as num?)?.toDouble() ?? 0,
    );
  }

  /// The `claude -p --output-format json` envelope: `usage` and
  /// `total_cost_usd`.
  factory fromClaude(Map<Object?, Object?> envelope) {
    final u = envelope['usage'];
    int n(String k) => u is Map ? (u[k] as num?)?.toInt() ?? 0 : 0;
    return Usage(
      input: n('input_tokens'),
      output: n('output_tokens'),
      cacheRead: n('cache_read_input_tokens'),
      cacheWrite: n('cache_creation_input_tokens'),
      costUsd: (envelope['total_cost_usd'] as num?)?.toDouble() ?? 0,
    );
  }

  /// An OpenAI-style chat response (OmniRoute).
  factory fromOpenAi(Map<Object?, Object?> body) {
    final u = body['usage'];
    if (u is! Map) return zero;
    final details = u['prompt_tokens_details'];
    return Usage(
      input: (u['prompt_tokens'] as num?)?.toInt() ?? 0,
      output: (u['completion_tokens'] as num?)?.toInt() ?? 0,
      cacheRead: details is Map
          ? (details['cached_tokens'] as num?)?.toInt() ?? 0
          : 0,
    );
  }

  /// An ollama chat response: `prompt_eval_count` and `eval_count`.
  factory fromOllama(Map<Object?, Object?> body) => Usage(
    input: (body['prompt_eval_count'] as num?)?.toInt() ?? 0,
    output: (body['eval_count'] as num?)?.toInt() ?? 0,
  );

  /// Nothing spent.
  static const zero = Usage();

  /// Prompt tokens.
  final int input;

  /// Completion tokens.
  final int output;

  /// Prompt tokens served from the cache.
  final int cacheRead;

  /// Prompt tokens written to the cache.
  final int cacheWrite;

  /// Dollars, when the API reports them.
  final double costUsd;

  /// Whether nothing is recorded.
  bool get isEmpty =>
      input == 0 &&
      output == 0 &&
      cacheRead == 0 &&
      cacheWrite == 0 &&
      costUsd == 0;

  /// The sum of both.
  Usage operator +(Usage o) => Usage(
    input: input + o.input,
    output: output + o.output,
    cacheRead: cacheRead + o.cacheRead,
    cacheWrite: cacheWrite + o.cacheWrite,
    costUsd: costUsd + o.costUsd,
  );

  /// The `tokens` object of `status.json`.
  Map<String, int> get tokens => {
    'in': input,
    'out': output,
    'cache_read': cacheRead,
    'cache_write': cacheWrite,
  };

  /// The usage object of a row: the four counters and `cost_usd`.
  Map<String, Object?> toJson() => {...tokens, 'cost_usd': costUsd};
}
