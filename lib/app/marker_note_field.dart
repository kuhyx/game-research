/// The note field of a marker that has none: Enter saves it into the
/// session's `markers.jsonl` (a copy needs a note, it is drawn into the
/// image). Esc leaves the field without closing the panel. A spinner shows
/// while it saves and the error glyph when the wrapper refused. No labels.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/doc_style.dart';
import 'package:game_research/app/notes_models.dart';
import 'package:material_ui/material_ui.dart';

/// Writes the note of [marker] through [api]; [onSaved] re-reads the notes.
class MarkerNoteField extends StatefulWidget {
  /// Creates the field.
  const new({
    required this.api,
    required this.marker,
    required this.onSaved,
    required this.style,
    super.key,
  });

  /// The wrapper client.
  final ResearchApi api;

  /// The marker without a note.
  final NoteMarker marker;

  /// Called once the note is saved.
  final VoidCallback onSaved;

  /// Sizes.
  final DocStyle style;

  @override
  State<MarkerNoteField> createState() => _MarkerNoteFieldState();
}

class _MarkerNoteFieldState extends State<MarkerNoteField> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _save(String text) async {
    final note = text.trim();
    if (note.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.api.setNote(widget.marker.session, widget.marker.i, note);
    } on Exception {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final m = widget.marker;
    final label = 'note text ${m.session} ${m.i}';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            FocusScope.of(context).unfocus(),
      },
      child: Semantics(
        label: label,
        child: TextField(
          enabled: !_busy,
          onSubmitted: _save,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: style.px(44),
            color: DocStyle.body,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.edit_note_rounded,
              color: DocStyle.muted,
              size: style.px(48),
            ),
            suffixIcon: _busy
                ? const CircularProgressIndicator()
                : _failed
                ? const Icon(
                    Icons.error_outline_rounded,
                    color: AppPalette.danger,
                    semanticLabel: 'note error',
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
