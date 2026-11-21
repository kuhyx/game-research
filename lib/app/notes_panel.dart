/// "My notes" of a game over the window: every message part as a card with
/// its copy icons, a row per marker (tag, time, note, thumbnail, copy). Stills
/// are cut lazily on the first read, so the list is re-read until every
/// marker has one. Icons and numbers only; the notes are kuhy's own text.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/doc_style.dart';
import 'package:game_research/app/notes_card.dart';
import 'package:game_research/app/notes_models.dart';
import 'package:material_ui/material_ui.dart';

/// The notes of game [appid]; fills the window.
class NotesPanel extends StatefulWidget {
  /// Reads the notes of [appid] through [api].
  const new({
    required this.api,
    required this.appid,
    required this.onClose,
    this.pollEvery = const Duration(seconds: 2),
    this.maxPolls = 60,
    super.key,
  });

  /// The wrapper client.
  final ResearchApi api;

  /// Steam app id.
  final int appid;

  /// Close pressed (or Esc).
  final VoidCallback onClose;

  /// Pause before the notes are read again while stills are missing.
  final Duration pollEvery;

  /// Most re-reads (the recording may be gone for good).
  final int maxPolls;

  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  List<NotePart>? _parts;
  bool _failed = false;
  int _polls = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final parts = await widget.api.notes(widget.appid);
      if (!mounted) return;
      setState(() => _parts = parts);
      final missing = parts.any((p) => p.markers.any((m) => !m.still));
      if (missing && _polls < widget.maxPolls) {
        _polls++;
        _timer = Timer(widget.pollEvery, _load);
      }
    } on Exception {
      // A failed re-read keeps what is on screen.
      if (mounted && _parts == null) setState(() => _failed = true);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Material(
      color: DocStyle.background,
      child: LayoutBuilder(
        builder: (context, box) {
          final style = DocStyle(
            width: box.maxWidth,
            height: box.maxHeight,
            dpr: dpr,
          );
          return Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: Stack(
              children: [
                Positioned.fill(child: _body(style)),
                Positioned(
                  top: style.px(24),
                  right: style.px(48),
                  child: Row(
                    children: [
                      KLogo(size: style.px(64)),
                      IconButton(
                        onPressed: widget.onClose,
                        color: DocStyle.body,
                        iconSize: style.px(64),
                        icon: const Icon(
                          Icons.close_rounded,
                          semanticLabel: 'close',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _body(DocStyle style) {
    final parts = _parts;
    if (parts == null) {
      return Center(
        child: _failed
            ? Icon(
                Icons.error_outline_rounded,
                color: AppPalette.danger,
                size: style.px(192),
                semanticLabel: 'notes error',
              )
            : const CircularProgressIndicator(),
      );
    }
    if (parts.isEmpty) {
      return Center(
        child: Icon(
          Icons.inbox_rounded,
          color: DocStyle.muted,
          size: style.px(192),
          semanticLabel: 'no notes',
        ),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: style.marginX,
        vertical: style.marginY,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: style.gutter,
          runSpacing: style.gutter,
          children: [
            for (final p in parts)
              NotesCard(
                api: widget.api,
                appid: widget.appid,
                part: p,
                style: style,
                onChanged: _load,
              ),
          ],
        ),
      ),
    );
  }
}
