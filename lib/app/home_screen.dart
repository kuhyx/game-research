/// The one window: games on the left; controls, target and past sessions on
/// the right. Polls the wrapper once a second (state, sessions); the games
/// and targets load once and on each session end.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/controls.dart';
import 'package:game_research/app/game_picker.dart';
import 'package:game_research/app/models.dart';
import 'package:game_research/app/session_list.dart';
import 'package:game_research/app/target_picker.dart';

/// The home screen.
class HomeScreen extends StatefulWidget {
  /// Creates the screen over [api].
  const new({
    required this.api,
    this.poll = const Duration(seconds: 1),
    this.now = _now,
    super.key,
  });

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
  Timer? _timer;

  ResearchApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
    _timer = Timer.periodic(widget.poll, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
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
  }

  Future<void> _refresh() async {
    try {
      final state = await _api.state();
      final sessions = await _api.sessions();
      if (!mounted) return;
      final ended = _state.recording && !state.recording;
      setState(() {
        _state = state;
        _sessions = sessions;
        _offline = false;
        if (state.appid != null) _picked = state.appid;
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

  Future<void> _marker(String tag) => _act(() async {
    final hold = await _api.marker(tag, hold: tag == 'note');
    if (hold != null) setState(() => _hold = hold);
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _offline
                    ? const Center(
                        child: Icon(
                          Icons.cloud_off_rounded,
                          size: 96,
                          color: AppPalette.danger,
                          semanticLabel: 'wrapper offline',
                        ),
                      )
                    : GamePicker(
                        games: _games,
                        selected: _picked,
                        enabled: !_state.recording,
                        capsuleUrl: _api.capsuleUrl,
                        onPick: (id) => setState(() => _picked = id),
                      ),
              ),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(
                width: 640,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Controls(
                      state: _state,
                      canStart: _picked != null,
                      elapsedS: started == null ? 0 : widget.now() - started,
                      noteOpen: _hold != null,
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
                        onRerun: (id) => _act(() => _api.analyze(id)),
                        onOpenDraft: (id) => _act(() => _api.openDraft(id)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
