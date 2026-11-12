/// What the page gets of a job's `status.json`: tolerant of old sessions
/// (no tokens, no eta) and of states this build does not know.
library;

import 'dart:io';

import 'package:game_research/core/safe_json.dart' as safe;

/// The JSON object in [f], or `{}` when missing or broken.
Map<String, Object?> readJson(File f) => safe.readJsonObject(f) ?? {};

const _states = {'idle', 'running', 'waiting', 'interrupted', 'done', 'failed'};

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// The status object of `/api/sessions` (`analysis`) and `/api/games`
/// (`finish`). `progress` is the file's own, else 0..1 over three stages.
Map<String, Object?> statusView(Map<String, Object?> raw) {
  final state = raw['state'] is String && _states.contains(raw['state'])
      ? raw['state']! as String
      : 'idle';
  final stage = _int(raw['stage']);
  final done = _int(raw['done']);
  final total = _int(raw['total']);
  final double progress;
  if (raw['progress'] is num) {
    progress = (raw['progress']! as num).toDouble();
  } else if (state == 'done') {
    progress = 1;
  } else if (stage <= 0) {
    progress = 0;
  } else {
    progress = ((stage - 1) + (total > 0 ? done / total : 0.0)) / 3;
  }
  return {
    'stage': stage,
    'done': done,
    'total': total,
    'state': state,
    'progress': progress,
    'tokens': raw['tokens'],
    'cost_usd': raw['cost_usd'],
    'eta_s': raw['eta_s'],
    if (raw['error'] is String) 'error': raw['error'],
  };
}
