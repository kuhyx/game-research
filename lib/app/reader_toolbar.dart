/// The reader's controls: hidden above the top edge, slid in while the mouse
/// is in a strip there (or over the bar), slid out when it leaves. A chevron
/// in the strip shows where the bar is hiding.
/// Icons and numbers only.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/copy_icon.dart';
import 'package:game_research/app/doc_style.dart';

/// Key of the bar itself (its position tells whether it is out).
const kReaderToolbarKey = ValueKey<String>('reader-toolbar');

/// Key of the always-visible cue at the top edge (fades while the bar is in).
const kReaderHandleKey = ValueKey<String>('reader-handle');

/// Reveals [bar] under the pointer at the top edge.
class HoverToolbar extends StatefulWidget {
  /// Wraps [bar]; sizes come from [style].
  const new({required this.style, required this.bar, super.key});

  /// Sizes.
  final DocStyle style;

  /// The bar; laid out at its own height.
  final Widget bar;

  @override
  State<HoverToolbar> createState() => _HoverToolbarState();
}

class _HoverToolbarState extends State<HoverToolbar> {
  bool _shown = false;

  void _set({required bool shown}) => setState(() => _shown = shown);

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final barHeight = style.px(96);
    const handleSemantic = 'toolbar';
    return MouseRegion(
      onEnter: (_) => _set(shown: true),
      onExit: (_) => _set(shown: false),
      child: SizedBox(
        height: _shown ? barHeight : style.px(48),
        width: double.infinity,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            AnimatedOpacity(
              key: kReaderHandleKey,
              opacity: _shown ? 0 : 1,
              duration: const Duration(milliseconds: 160),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: DocStyle.muted,
                size: style.px(48),
                semanticLabel: handleSemantic,
              ),
            ),
            OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: barHeight,
              maxHeight: barHeight,
              child: IgnorePointer(
                ignoring: !_shown,
                child: ExcludeSemantics(
                  excluding: !_shown,
                  child: AnimatedSlide(
                    offset: _shown ? Offset.zero : const Offset(0, -1),
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    child: SizedBox(
                      key: kReaderToolbarKey,
                      height: barHeight,
                      child: widget.bar,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bar's content: edit, save, copy short, notes, state glyphs, page
/// position, close.
class ReaderBar extends StatelessWidget {
  /// The bar for the current state.
  const new({
    required this.style,
    required this.loaded,
    required this.editing,
    required this.canSave,
    required this.failed,
    required this.saved,
    required this.page,
    required this.pageCount,
    required this.onEdit,
    required this.onSave,
    required this.onClose,
    this.onCopyShort,
    this.onNotes,
    super.key,
  });

  /// Sizes.
  final DocStyle style;

  /// The document is loaded (edit is on).
  final bool loaded;

  /// Edit mode.
  final bool editing;

  /// Unsaved edits exist.
  final bool canSave;

  /// The last load or save failed.
  final bool failed;

  /// The last save went through.
  final bool saved;

  /// Zero-based page shown; null in edit mode.
  final int? page;

  /// Number of pages.
  final int pageCount;

  /// Edit toggle.
  final VoidCallback onEdit;

  /// Save pressed.
  final VoidCallback onSave;

  /// Close pressed.
  final VoidCallback onClose;

  /// Copies the Discord version; null = there is none (the icon is off).
  final Future<void> Function()? onCopyShort;

  /// Opens the game's notes; null = no game behind this document.
  final VoidCallback? onNotes;

  @override
  Widget build(BuildContext context) {
    const editSemantic = 'edit';
    const saveSemantic = 'save';
    const closeSemantic = 'close';
    const notesSemantic = 'my notes';
    const failedSemantic = 'document error';
    const pageSemantic = 'page';
    final size = style.px(48);
    final pos = page == null ? null : '${page! + 1}/$pageCount';
    return ColoredBox(
      color: const Color(0xFF20232A),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: style.marginX / 2),
        child: Row(
          children: [
            IconButton(
              onPressed: loaded ? onEdit : null,
              color: DocStyle.body,
              iconSize: size,
              icon: Icon(
                editing ? Icons.visibility_rounded : Icons.edit_rounded,
                semanticLabel: editSemantic,
              ),
            ),
            IconButton(
              onPressed: editing && canSave ? onSave : null,
              color: DocStyle.body,
              iconSize: size,
              icon: const Icon(Icons.save_rounded, semanticLabel: saveSemantic),
            ),
            CopyIcon(semantic: 'copy short', size: size, onCopy: onCopyShort),
            if (onNotes != null)
              IconButton(
                onPressed: onNotes,
                color: DocStyle.body,
                iconSize: size,
                icon: const Icon(
                  Icons.sticky_note_2_rounded,
                  semanticLabel: notesSemantic,
                ),
              ),
            if (failed && loaded)
              Icon(
                Icons.error_outline_rounded,
                color: AppPalette.danger,
                size: size,
                semanticLabel: failedSemantic,
              ),
            if (saved && !canSave)
              Icon(Icons.check_rounded, color: AppPalette.success, size: size),
            const Spacer(),
            if (pos != null)
              Semantics(
                container: true,
                label: pageSemantic,
                value: pos,
                excludeSemantics: true,
                child: Text(
                  pos,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: style.bodySize,
                    color: DocStyle.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            const Spacer(),
            IconButton(
              onPressed: onClose,
              color: DocStyle.body,
              iconSize: size,
              icon: const Icon(
                Icons.close_rounded,
                semanticLabel: closeSemantic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
