/// One real caption call through one tier, for the tier smoke checks:
/// `dart run tool/smoke_tier.dart <haiku|omniroute|ollama> <frame.png>`.
/// Prints the caption record; exit 0 only when that tier captioned it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_research/analysis/tiers.dart';
import 'package:game_research/core/captions.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final config = Config.fromEnv(
    {...Platform.environment}..remove('GAME_RESEARCH_FAKE_LLM'),
    cwd: Directory.current.path,
  );
  final client = http.Client();
  final tier = captionTiers(
    config,
    const Sys(),
    client,
  ).firstWhere((t) => t.name == args[0]);
  final rec = await captionWithFallback([tier], args[1], t: 0);
  client.close();
  stdout.writeln(jsonEncode(rec.toJson()));
  exitCode = rec.ok ? 0 : 1;
}
