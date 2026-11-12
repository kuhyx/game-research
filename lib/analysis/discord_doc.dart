/// Writes the Discord version of a research document (`X.discord.md`, see
/// `core/discord_doc.dart`): one Opus call, the code checks the answer, ONE
/// rewrite names each violation, then it fails closed.
///
/// A job never fails because of it: [discordOutcome] turns every failure
/// into the text kept in the job state (`failed: <reason>`), leaves the
/// document untouched and writes no sibling.
library;

import 'dart:io';

import 'package:game_research/analysis/job.dart';
import 'package:game_research/analysis/line_cap.dart';
import 'package:game_research/analysis/tiers.dart';
import 'package:game_research/core/captions.dart';
import 'package:game_research/core/discord_doc.dart';
import 'package:game_research/core/safe_json.dart';
import 'package:game_research/core/synthesis.dart';
import 'package:game_research/core/usage.dart';
import 'package:game_research/desktop/config.dart';
import 'package:game_research/desktop/sys.dart';
import 'package:path/path.dart' as p;

/// One Opus call: the prompt, the file it was saved to; the answer text.
/// Throws [WaitingError] at a usage limit, [StateError] on any other error.
typedef DiscordAsk = Future<String> Function(String prompt, String promptFile);

/// The job state kept when the short version was written.
const kDiscordOk = 'ok';

/// Writes the short version of [docPath] next to it, replacing an older one.
/// [workDir] keeps the prompt and the over-long answer. Throws when Claude
/// fails, its answer lacks the envelope, or a violation is left after the one
/// rewrite; nothing is written then.
Future<void> writeDiscord(
  String docPath,
  DiscordAsk ask,
  String workDir,
) async {
  if (!File(docPath).existsSync()) throw StateError('no document $docPath');
  final sibling = discordPathOf(docPath);
  Directory(workDir).createSync(recursive: true);
  final prompt = buildDiscordPrompt(docPath);
  final promptFile = File(p.join(workDir, 'discord_prompt.txt'))
    ..writeAsStringSync(prompt);
  final text = await parseWithinCap(
    raw: await ask(prompt, promptFile.path),
    parse: parseDiscord,
    violations: discordViolations,
    longFile: File(p.join(workDir, 'discord_long.txt')),
    format: '$kDiscordMarker\n<the shortened markdown>\n$kEndMarker',
    cap: '$kDiscordMax characters',
    promptFor: ({required longFile, required violations, required format}) =>
        discordRewritePrompt(
          docPath: docPath,
          longFile: longFile,
          violations: violations,
          format: format,
        ),
    shorten: (q) {
      final file = File(p.join(workDir, 'discord_rewrite_prompt.txt'))
        ..writeAsStringSync(q);
      return ask(q, file.path);
    },
  );
  writeAtomic(File(sibling), '$text\n');
}

/// The job-state text for the failure [e]: `failed: <reason>` on one line.
String discordFailure(Object e) {
  final why = (e is StateError ? e.message : '$e')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return 'failed: ${why.length > 200 ? why.substring(0, 200) : why}';
}

/// [writeDiscord] that never throws: [kDiscordOk], or [discordFailure], for
/// the job state.
Future<String> discordOutcome(
  String docPath,
  DiscordAsk ask,
  String workDir,
) async {
  try {
    await writeDiscord(docPath, ask, workDir);
    return kDiscordOk;
  } on Object catch (e) {
    return discordFailure(e);
  }
}

/// Deletes the short version of [docPath] (stale once the doc changed).
void dropDiscord(String docPath) {
  final sibling = File(discordPathOf(docPath));
  if (sibling.existsSync()) sibling.deleteSync();
}

/// One Opus call (the fake model under test), for jobs that keep no tally of
/// their own: [spent] gets the call's usage whatever the answer. A usage limit
/// is a [WaitingError], any other error a [StateError].
Future<String> askOpus({
  required Config config,
  required Sys sys,
  required String prompt,
  required String promptFile,
  required List<String> dirs,
  required void Function(Usage spent) spent,
}) async {
  final answer = config.fakeLlm.isNotEmpty
      ? await FakeTier(config, sys, 'opus').call(promptFile)
      : await ClaudeTier(
          config,
          sys,
          model: 'opus',
          limitS: 1500,
        ).ask(prompt, dirs);
  spent(answer.usage);
  final error = answer.error;
  if (error != null) {
    if (isRateLimited(error)) throw WaitingError('discord: $error');
    throw StateError('discord failed: $error');
  }
  return answer.text;
}
