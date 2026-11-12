/// Owns the draft/report panel and the row/tile actions that open it or
/// start a job, all behind the [TapGuard]. The builder draws the screen
/// and calls the PanelActions; the panel covers it while open.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/models.dart';
import 'package:game_research/app/report_panel.dart';
import 'package:game_research/app/tap_guard.dart';

/// What the screen can ask of the host.
class PanelActions {
  /// Creates the actions.
  const new({
    required this.openDraft,
    required this.rerun,
    required this.finish,
  });

  /// Opens the draft of session id.
  final ValueChanged<String> openDraft;

  /// Reruns the analysis of session id.
  final ValueChanged<String> rerun;

  /// The flag of a game tile: open its report, or merge its drafts.
  final ValueChanged<Game> finish;
}

/// The host.
class PanelHost extends StatefulWidget {
  /// Creates the host over [sessions].
  const new({
    required this.api,
    required this.guard,
    required this.sessions,
    required this.act,
    required this.builder,
    super.key,
  });

  /// The wrapper client.
  final ResearchApi api;

  /// Quiet period after the screen changed under the pointer.
  final TapGuard guard;

  /// Past sessions (draft paths, which games have drafts).
  final List<SessionRow> sessions;

  /// Runs a call and refreshes the screen afterwards.
  final Future<void> Function(Future<void> Function()) act;

  /// Draws the screen.
  final Widget Function(PanelActions actions) builder;

  @override
  State<PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<PanelHost> {
  /// The open document; finishAppid is set for a report (rerunnable).
  ({String path, int? finishAppid})? _panel;

  void _openDraft(String id) => widget.guard.run(() {
    final draft = widget.sessions.where((r) => r.id == id).firstOrNull?.draft;
    if (draft != null) {
      setState(() => _panel = (path: draft, finishAppid: null));
    }
  });

  void _rerun(String id) => widget.guard.run(
    () => unawaited(widget.act(() => widget.api.analyze(id))),
  );

  void _finish(Game g) => widget.guard.run(() {
    final f = g.finish;
    if (f != null && f.state == 'done' && f.report != null) {
      setState(() => _panel = (path: f.report!, finishAppid: g.appid));
    } else if (!(f?.job.active ?? false) && _hasDraft(g.appid)) {
      unawaited(widget.act(() => widget.api.finish(g.appid)));
    }
  });

  bool _hasDraft(int appid) =>
      widget.sessions.any((r) => r.appid == appid && r.draft != null);

  @override
  Widget build(BuildContext context) {
    final panel = _panel;
    return Stack(
      children: [
        widget.builder(
          PanelActions(openDraft: _openDraft, rerun: _rerun, finish: _finish),
        ),
        if (panel != null)
          Positioned.fill(
            child: ColoredBox(
              color: AppPalette.ink.withValues(alpha: 0.9),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ReportPanel(
                  api: widget.api,
                  path: panel.path,
                  onClose: () => setState(() => _panel = null),
                  onRerun: panel.finishAppid == null
                      ? null
                      : () => unawaited(
                          widget.act(
                            () => widget.api.finish(panel.finishAppid!),
                          ),
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
