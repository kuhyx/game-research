/// The in-app reader of a draft or report: the document paged onto full
/// screens (3 columns, never scrolled), an edit toggle (raw markdown) and
/// save. The wrapper only serves files under the target's `docs/research/`.
/// Icons and numbers only; the document is the user's own content.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/doc_blocks.dart';
import 'package:game_research/app/doc_page_view.dart';
import 'package:game_research/app/doc_pager.dart';
import 'package:game_research/app/doc_style.dart';
import 'package:game_research/app/reader_body.dart';
import 'package:game_research/app/reader_toolbar.dart';

/// The panel for the document at [path]; fills the window.
class ReportPanel extends StatefulWidget {
  /// Opens [path] through [api].
  const new({
    required this.api,
    required this.path,
    required this.onClose,
    super.key,
  });

  /// The wrapper client.
  final ResearchApi api;

  /// Absolute path of the document.
  final String path;

  /// Close pressed (or Esc).
  final VoidCallback onClose;

  @override
  State<ReportPanel> createState() => _ReportPanelState();
}

class _ReportPanelState extends State<ReportPanel> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  String? _saved;
  bool _editing = false;
  bool _failed = false;
  bool _justSaved = false;
  int _page = 0;
  List<DocPage> _pages = [DocPage()];
  (String, double, double, double)? _laidOutFor;

  bool get _dirty => _saved != null && _field.text != _saved;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(ReportPanel old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _saved = null;
      _editing = false;
      _page = 0;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final text = await widget.api.doc(widget.path);
      if (!mounted) return;
      setState(() {
        _saved = text;
        _field.text = text;
        _failed = false;
      });
    } on Exception {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _save() async {
    final text = _field.text;
    try {
      await widget.api.saveDoc(widget.path, text);
      if (!mounted) return;
      setState(() {
        _saved = text;
        _failed = false;
        _justSaved = true;
      });
    } on Exception {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _toggleEdit() {
    setState(() {
      _editing = !_editing;
      _justSaved = false;
    });
    _focus.requestFocus();
  }

  void _flip(int by) =>
      setState(() => _page = (_page + by).clamp(0, _pages.length - 1));

  /// Esc leaves edit mode first (the edit stays, unsaved); otherwise closes,
  /// except with unsaved edits, which only the close icon may discard.
  /// Arrows and PageUp/PageDown flip pages, never while editing.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_editing) {
        _toggleEdit();
      } else if (!_dirty) {
        widget.onClose();
      }
      return KeyEventResult.handled;
    }
    if (_editing || _saved == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown) {
      _flip(1);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _flip(-1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is PointerScrollEvent && !_editing && _saved != null) {
      _flip(event.scrollDelta.dy > 0 ? 1 : -1);
    }
  }

  /// Pages of the text at [style]; measured again only when the text or the
  /// window changed.
  List<DocPage> _pagesFor(DocStyle style) {
    final key = (_field.text, style.width, style.height, style.dpr);
    if (_laidOutFor != key) {
      _laidOutFor = key;
      _pages = paginate(parseDoc(_field.text), style);
    }
    return _pages;
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
          final loaded = _saved != null;
          final reading = loaded && !_editing;
          final pages = reading ? _pagesFor(style) : const <DocPage>[];
          final page = reading ? _page.clamp(0, pages.length - 1) : 0;
          return Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: Stack(
              children: [
                Positioned.fill(child: _body(style, pages, page)),
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: HoverToolbar(
                      style: style,
                      bar: ReaderBar(
                        style: style,
                        loaded: loaded,
                        editing: _editing,
                        canSave: _dirty,
                        failed: _failed,
                        saved: _justSaved,
                        page: reading ? page : null,
                        pageCount: pages.length,
                        onEdit: _toggleEdit,
                        onSave: _save,
                        onClose: widget.onClose,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _body(DocStyle style, List<DocPage> pages, int page) {
    if (_saved == null) {
      return ReaderPlaceholder(style: style, failed: _failed);
    }
    if (_editing) {
      return ReaderEditor(
        style: style,
        controller: _field,
        onChanged: () => setState(() => _justSaved = false),
      );
    }
    return Listener(
      onPointerSignal: _onWheel,
      child: DocPageView(page: pages[page], style: style),
    );
  }
}
