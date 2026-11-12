/// One message part of kuhy's notes as a card: a `n/of` header with the two
/// copy icons (the images with the notes drawn in: big, first; the plain text:
/// small, muted, after it), then a row per marker. Icons, numbers and the
/// notes kuhy typed himself; no labels.
library;

import 'package:flutter/material.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/copy_icon.dart';
import 'package:game_research/app/doc_style.dart';
import 'package:game_research/app/notes_models.dart';
import 'package:game_research/app/notes_row.dart';

const _tabular = [FontFeature.tabularFigures()];

/// A part of game [appid]'s notes.
class NotesCard extends StatelessWidget {
  /// Draws [part] at [style]; copies go through [api].
  const new({
    required this.api,
    required this.appid,
    required this.part,
    required this.style,
    required this.onChanged,
    super.key,
  });

  /// A note was saved: re-read the notes.
  final VoidCallback onChanged;

  /// The wrapper client.
  final ResearchApi api;

  /// The game.
  final int appid;

  /// The part.
  final NotePart part;

  /// Sizes.
  final DocStyle style;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    String? date;
    for (final m in part.markers) {
      if (m.date != date) {
        date = m.date;
        rows.add(_DateRow(date: date, style: style));
      }
      rows.add(
        MarkerRow(api: api, marker: m, style: style, onChanged: onChanged),
      );
    }
    return Container(
      width: style.px(1700),
      padding: EdgeInsets.all(style.px(32)),
      decoration: BoxDecoration(
        color: const Color(0xFF20232A),
        borderRadius: BorderRadius.circular(style.px(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${part.n}/${part.of}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: style.px(52),
                  color: DocStyle.heading,
                  fontFeatures: _tabular,
                ),
              ),
              const Spacer(),
              CopyIcon(
                semantic: 'copy notes ${part.n} files',
                glyph: Icons.photo_library_rounded,
                size: style.px(80),
                onCopy: part.hasStills && part.hasNotes
                    ? () => api.copyPart(appid, part.n, 'files')
                    : null,
              ),
              CopyIcon(
                semantic: 'copy notes ${part.n} text',
                glyph: Icons.text_snippet_rounded,
                size: style.px(48),
                color: DocStyle.muted,
                onCopy: part.hasNotes
                    ? () => api.copyPart(appid, part.n, 'text')
                    : null,
              ),
            ],
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const new({required this.date, required this.style});

  final String date;
  final DocStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: style.px(20), bottom: style.px(8)),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_rounded,
            color: DocStyle.muted,
            size: style.px(40),
          ),
          SizedBox(width: style.px(16)),
          Text(
            date,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: style.px(40),
              color: DocStyle.muted,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }
}
