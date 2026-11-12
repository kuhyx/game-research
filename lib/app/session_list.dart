/// Past sessions: capsule, start date and length as numbers, marker counts,
/// the analysis ring and its numbers, draft and report buttons. No
/// words.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/game_picker.dart';
import 'package:game_research/app/marker_style.dart';
import 'package:game_research/app/models.dart';
import 'package:game_research/app/stat_chips.dart';

/// The list.
class SessionList extends StatelessWidget {
  /// Creates the list.
  const new({
    required this.sessions,
    required this.capsuleUrl,
    required this.onOpenDraft,
    this.reportReady = const {},
    this.onOpenReport,
    super.key,
  });

  /// Rows, newest first.
  final List<SessionRow> sessions;

  /// Capsule URL of an app id.
  final String Function(int appid) capsuleUrl;

  /// Open draft pressed for a session id.
  final ValueChanged<String> onOpenDraft;

  /// App ids whose game report is finished and can be opened.
  final Set<int> reportReady;

  /// Report pressed on a row of app id.
  final ValueChanged<int>? onOpenReport;

  @override
  Widget build(BuildContext context) => ListView.separated(
    itemCount: sessions.length,
    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
    itemBuilder: (context, i) => _Row(
      row: sessions[i],
      capsuleUrl: capsuleUrl,
      onOpenDraft: onOpenDraft,
      onOpenReport: reportReady.contains(sessions[i].appid)
          ? onOpenReport
          : null,
    ),
  );
}

/// `MM-DD HH:MM` of a unix time, local.
String stamp(double unix) {
  final d = DateTime.fromMillisecondsSinceEpoch((unix * 1000).round());
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

class _Row extends StatelessWidget {
  const new({
    required this.row,
    required this.capsuleUrl,
    required this.onOpenDraft,
    required this.onOpenReport,
  });

  final SessionRow row;
  final String Function(int) capsuleUrl;
  final ValueChanged<String> onOpenDraft;
  final ValueChanged<int>? onOpenReport;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ring = switch (row.state) {
      'done' => AppPalette.success,
      'failed' => AppPalette.danger,
      'waiting' || 'interrupted' => AppPalette.warning,
      _ => AppPalette.accent,
    };
    final draftSemantic = 'draft ${row.id}';
    final ringSemantic = 'analysis ${row.state}';
    final reportSemantic = 'report ${row.id}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 48,
                height: 72,
                child: Image.network(
                  capsuleUrl(row.appid),
                  fit: BoxFit.cover,
                  semanticLabel: row.game,
                  errorBuilder: (_, _, _) =>
                      ProceduralCapsule(appid: row.appid),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stamp(row.startedUnix), style: text.titleMedium),
                  Text(
                    clock(row.durationS),
                    style: text.bodyMedium?.copyWith(
                      color: AppPalette.mutedOnDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      for (final s in kMarkerStyles)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(s.icon, size: 20, color: s.color),
                            Text('${row.counts[s.tag] ?? 0}'),
                          ],
                        ),
                    ],
                  ),
                  StatChips(job: row.job, fpsAvg: row.fpsAvg, words: true),
                ],
              ),
            ),
            Semantics(
              label: ringSemantic,
              value: '${(row.progress * 100).round()}',
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: row.progress,
                      strokeWidth: 5,
                      color: ring,
                      backgroundColor: AppPalette.lineDark,
                    ),
                    if (row.state == 'failed')
                      const Icon(
                        Icons.priority_high_rounded,
                        color: AppPalette.danger,
                      ),
                    if (row.state == 'done')
                      const Icon(
                        Icons.check_rounded,
                        color: AppPalette.success,
                      ),
                    if (row.state == 'waiting')
                      const Icon(
                        Icons.hourglass_top_rounded,
                        color: AppPalette.warning,
                      ),
                    if (row.state == 'interrupted')
                      const Icon(
                        Icons.pause_rounded,
                        color: AppPalette.warning,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: row.draft == null ? null : () => onOpenDraft(row.id),
              icon: Icon(
                Icons.description_rounded,
                semanticLabel: draftSemantic,
              ),
              iconSize: 32,
            ),
            if (onOpenReport != null)
              IconButton(
                onPressed: () => onOpenReport!(row.appid),
                icon: Icon(
                  Icons.summarize_rounded,
                  color: AppPalette.success,
                  semanticLabel: reportSemantic,
                ),
                iconSize: 32,
              ),
          ],
        ),
      ),
    );
  }
}
