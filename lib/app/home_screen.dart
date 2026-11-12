/// The one window: games on the left; controls, target and past sessions on
/// the right. Polls the wrapper once a second (state, sessions, finish
/// states); games and targets load once and on each session end.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/controls.dart';
import 'package:game_research/app/game_picker.dart';
import 'package:game_research/app/models.dart';
import 'package:game_research/app/panel_host.dart';
import 'package:game_research/app/session_list.dart';
import 'package:game_research/app/tap_guard.dart';
import 'package:game_research/app/target_picker.dart';

/// The home screen.
class HomeScreen extends StatefulWidget {
  /// Creates the screen over [api].
  const new({
    required this.api,
    this.poll = const Duration(seconds: 1),
    this.now = _now,
    this.autostart = false,
    super.key,
  });

  /// Opened by the launcher (`?autostart=1`): arm the autostart ring.
  final bool autostart;

  /// The wrapper client.
  final ResearchApi api;

  /// Poll interval.
  final Duration poll;

  /// Wall clock, unix seconds (fixed in tests).
  final double Function() now;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

double _now() => DateTime.now().millisecondsSinceEpoch / 1000;

class _HomeScreenState extends State<HomeScreen> {
  List<Game> _games = const [];
  TargetList _targets = const TargetList();
  List<SessionRow> _sessions = const [];
  AppState _state = const AppState();
  int? _picked;
  int? _hold;
  bool _offline = false;
  bool _armed = false;
  Timer? _timer;
  final _guard = TapGuard();
  ResearchApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    // A page opened by the launcher gets clicks meant for Steam's windows.
    if (widget.autostart) _guard.hush();
    unawaited(_loadAll());
    _timer = Timer.periodic(widget.poll, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _guard.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final first = _games.isEmpty && _sessions.isEmpty && !_state.recording;
    try {
      final games = await _api.games();
      final targets = await _api.targets();
      if (!mounted) return;
      setState(() {
        _games = games;
        _targets = targets;
        _picked ??= games.length == 1 ? games.single.appid : null;
      });
    } on Exception {
      if (mounted) setState(() => _offline = true);
    }
    await _refresh();
    if (first && widget.autostart && !_armed && _state.phase == 'idle') {
      _armed = true;
      await _act(_api.autostart);
    }
  }

  Future<void> _refresh() async {
    try {
      final state = await _api.state();
      final sessions = await _api.sessions();
      // null: an older wrapper without /api/finish
      final finishes = await _api.finishes().then<Map<int, Finish>?>(
        (m) => m,
        onError: (Object _) => null,
      );
      if (!mounted) return;
      final ended = _state.recording && !state.recording;
      // A game or Steam window opened or closed over this one.
      if (state.phase != _state.phase) _guard.hush();
      setState(() {
        _state = state;
        _sessions = sessions;
        if (finishes != null) {
          _games = [for (final g in _games) g.withFinish(finishes[g.appid])];
        }
        _offline = false;
        _picked = state.appid ?? state.pendingAppid ?? _picked;
        if (!state.recording) _hold = null;
      });
      if (ended) unawaited(_loadAll());
    } on Exception {
      if (mounted) setState(() => _offline = true);
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
    } on ApiError {
      // The wrapper keeps the reason in /api/state; the next poll shows it.
    }
    await _refresh();
  }

  /// Every marker opens the note line; a still-open one closes empty first.
  Future<void> _marker(String tag) => _act(() async {
    final open = _hold;
    if (open != null) await _api.note(open, '');
    final hold = await _api.marker(tag, hold: true);
    setState(() => _hold = hold);
  });

  Future<void> _note(String text) {
    final id = _hold;
    setState(() => _hold = null);
    // A second submit before the field closes finds no hold.
    if (id == null) return Future.value(); // coverage:ignore-line
    return _act(() => _api.note(id, text));
  }

  @override
  Widget build(BuildContext context) {
    final started = _state.startedUnix;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_state.pending) unawaited(_act(_api.cancelAutostart));
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: PanelHost(
              api: _api,
              guard: _guard,
              sessions: _sessions,
              games: _games,
              act: _act,
              builder: (actions) => Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: _columns(started, actions),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _columns(double? started, PanelActions actions) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: GamePicker(
            games: _games,
            offline: _offline,
            selected: _picked,
            enabled: !_state.recording && !_state.pending,
            capsuleUrl: _api.capsuleUrl,
            onPick: (id) => setState(() => _picked = id),
            finishReady: {
              for (final r in _sessions)
                if (r.draft != null) r.appid,
            },
            onFinish: actions.finish,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        SizedBox(
          // 760: room for icon, count and hotkey legend per marker.
          width: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Controls(
                state: _state,
                canStart: _picked != null,
                elapsedS: started == null ? 0 : widget.now() - started,
                noteOpen: _hold != null,
                now: widget.now,
                onStart: () => _act(() => _api.start(_picked!)),
                onStop: () => _act(_api.stop),
                onMarker: _marker,
                onNote: _note,
              ),
              const SizedBox(height: AppSpacing.md),
              TargetPicker(
                paths: _targets.paths,
                current: _state.target.isEmpty
                    ? _targets.current
                    : _state.target,
                onPick: (path) => _act(() async {
                  await _api.pickTarget(path);
                  final targets = await _api.targets();
                  if (mounted) setState(() => _targets = targets);
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: SessionList(
                  sessions: _sessions,
                  capsuleUrl: _api.capsuleUrl,
                  onRerun: actions.rerun,
                  onOpenDraft: actions.openDraft,
                  reportReady: actions.reportReady,
                  onOpenReport: actions.openReport,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
