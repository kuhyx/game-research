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
    required this.openReport,
    required this.reportReady,
  });

  /// Opens the draft of session id.
  final ValueChanged<String> openDraft;

  /// Reruns the analysis of session id.
  final ValueChanged<String> rerun;

  /// The flag of a game tile: open its report, or queue the finish job.
  final ValueChanged<Game> finish;

  /// Opens the finished report of app id (a session row's button).
  final ValueChanged<int> openReport;

  /// App ids whose finished report can be opened.
  final Set<int> reportReady;
}

/// The host.
class PanelHost extends StatefulWidget {
  /// Creates the host over [sessions].
  const new({
    required this.api,
    required this.guard,
    required this.sessions,
    required this.games,
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

  /// Installed games with their finish state.
  final List<Game> games;

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

  /// The report of a finished game, behind the tap guard (a stray click
  /// must not open a panel).
  bool _canOpen(Game g) =>
      g.finish?.state == 'done' && g.finish?.report != null;

  void _openReport(Game g) => widget.guard.run(() {
    setState(() => _panel = (path: g.finish!.report!, finishAppid: g.appid));
  });

  /// Done: open the report. Otherwise always send the request (the wrapper
  /// records it durably and queues the job); not behind the guard: queuing
  /// is harmless, and a click eaten there once lost kuhy's request. A job
  /// that already works or waits needs no second request.
  void _finish(Game g) {
    if (_canOpen(g)) return _openReport(g);
    if (g.finish?.job.active ?? false) return;
    unawaited(widget.act(() => widget.api.finish(g.appid)));
  }

  void _report(int appid) {
    final g = widget.games.where((g) => g.appid == appid).firstOrNull;
    if (g != null && _canOpen(g)) _openReport(g);
  }

  @override
  Widget build(BuildContext context) {
    final panel = _panel;
    return Stack(
      children: [
        widget.builder(
          PanelActions(
            openDraft: _openDraft,
            rerun: _rerun,
            finish: _finish,
            openReport: _report,
            reportReady: {
              for (final g in widget.games)
                if (_canOpen(g)) g.appid,
            },
          ),
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
