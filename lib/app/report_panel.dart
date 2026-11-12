/// The in-app viewer of a draft or report: markdown rendered, an edit toggle
/// (plain text) and save. The wrapper only serves files under the target's
/// `docs/research/`. Icons only; the document is the user's own content.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:game_research/app/api.dart';

/// The panel for the document at [path].
class ReportPanel extends StatefulWidget {
  /// Opens [path] through [api]. [onRerun] adds a rerun button (reports).
  const new({
    required this.api,
    required this.path,
    required this.onClose,
    this.onRerun,
    super.key,
  });

  /// The wrapper client.
  final ResearchApi api;

  /// Absolute path of the document.
  final String path;

  /// Close pressed (or Esc).
  final VoidCallback onClose;

  /// Rerun pressed; null hides the button.
  final VoidCallback? onRerun;

  @override
  State<ReportPanel> createState() => _ReportPanelState();
}

class _ReportPanelState extends State<ReportPanel> {
  final _field = TextEditingController();
  String? _saved;
  bool _editing = false;
  bool _failed = false;
  bool _justSaved = false;

  bool get _dirty => _saved != null && _field.text != _saved;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ReportPanel old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _saved = null;
      _editing = false;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _field.dispose();
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

  @override
  Widget build(BuildContext context) {
    const editSemantic = 'edit';
    const saveSemantic = 'save';
    const rerunSemantic = 'rerun';
    const closeSemantic = 'close';
    const failedSemantic = 'document error';
    final loaded = _saved != null;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                IconButton(
                  onPressed: loaded
                      ? () => setState(() {
                          _editing = !_editing;
                          _justSaved = false;
                        })
                      : null,
                  icon: Icon(
                    _editing ? Icons.visibility_rounded : Icons.edit_rounded,
                    semanticLabel: editSemantic,
                  ),
                  iconSize: 32,
                ),
                IconButton(
                  onPressed: _editing && _dirty ? _save : null,
                  icon: const Icon(
                    Icons.save_rounded,
                    semanticLabel: saveSemantic,
                  ),
                  iconSize: 32,
                ),
                if (widget.onRerun != null)
                  IconButton(
                    onPressed: widget.onRerun,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      semanticLabel: rerunSemantic,
                    ),
                    iconSize: 32,
                  ),
                const SizedBox(width: AppSpacing.sm),
                if (_failed && loaded)
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppPalette.danger,
                    size: 32,
                    semanticLabel: failedSemantic,
                  ),
                if (_justSaved && !_dirty)
                  const Icon(
                    Icons.check_rounded,
                    color: AppPalette.success,
                    size: 32,
                  ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(
                    Icons.close_rounded,
                    semanticLabel: closeSemantic,
                  ),
                  iconSize: 32,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body(loaded, failedSemantic)),
        ],
      ),
    );
  }

  Widget _body(bool loaded, String failedSemantic) {
    if (!loaded) {
      return Center(
        child: _failed
            ? Icon(
                Icons.error_outline_rounded,
                color: AppPalette.danger,
                size: 96,
                semanticLabel: failedSemantic,
              )
            : const CircularProgressIndicator(),
      );
    }
    if (_editing) {
      const fieldSemantic = 'document text';
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Semantics(
          label: fieldSemantic,
          child: TextField(
            controller: _field,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace'),
            onChanged: (_) => setState(() => _justSaved = false),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: MarkdownBody(data: _field.text),
        ),
      ),
    );
  }
}
