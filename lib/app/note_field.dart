/// The one-line note field under the marker buttons: Enter saves, Esc
/// closes without text.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The note field.
class NoteField extends StatelessWidget {
  /// Creates the field.
  const new({required this.onNote, super.key});

  /// The text submitted ('' = closed by Esc).
  final ValueChanged<String> onNote;

  @override
  Widget build(BuildContext context) {
    const semanticLabel = 'note text';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => onNote(''),
        },
        child: Semantics(
          label: semanticLabel,
          child: TextField(
            autofocus: true,
            onSubmitted: onNote,
            decoration: const InputDecoration(
              prefixIcon: Icon(
                Icons.edit_note_rounded,
                color: Color(0xFF2F6FE2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
