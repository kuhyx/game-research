/// One marker line of the notes view: tag icon, time, the note kuhy wrote (or
/// a field to write it: a copy needs it), the still's thumbnail and the copy
/// icon of the single marker (off until the still is cut and a note exists).
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/copy_icon.dart';
import 'package:game_research/app/doc_style.dart';
import 'package:game_research/app/marker_note_field.dart';
import 'package:game_research/app/marker_style.dart';
import 'package:game_research/app/notes_models.dart';

const _tabular = [FontFeature.tabularFigures()];

/// A marker row; [onChanged] runs after a note was saved.
class MarkerRow extends StatelessWidget {
  /// Draws [marker] at [style].
  const new({
    required this.api,
    required this.marker,
    required this.style,
    required this.onChanged,
    super.key,
  });

  /// The wrapper client.
  final ResearchApi api;

  /// The marker.
  final NoteMarker marker;

  /// Sizes.
  final DocStyle style;

  /// A note was saved: re-read the notes.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final look = kMarkerStyles.firstWhere(
      (s) => s.tag == marker.tag,
      orElse: () => kMarkerStyles.last,
    );
    final text = TextStyle(
      fontFamily: 'Inter',
      fontSize: style.px(44),
      color: DocStyle.body,
      fontFeatures: _tabular,
    );
    return SizedBox(
      height: style.px(164),
      child: Row(
        children: [
          Icon(look.icon, color: look.color, size: style.px(64)),
          SizedBox(width: style.px(20)),
          Text(marker.time, style: text),
          SizedBox(width: style.px(24)),
          Expanded(
            child: marker.hasNote
                ? Text(
                    marker.note,
                    style: text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : MarkerNoteField(
                    api: api,
                    marker: marker,
                    onSaved: onChanged,
                    style: style,
                  ),
          ),
          _Thumb(api: api, marker: marker, style: style),
          CopyIcon(
            semantic: 'copy marker ${marker.session} ${marker.i}',
            size: style.px(64),
            onCopy: marker.still && marker.hasNote
                ? () => api.copyMarker(marker.session, marker.i)
                : null,
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const new({required this.api, required this.marker, required this.style});

  final ResearchApi api;
  final NoteMarker marker;
  final DocStyle style;

  @override
  Widget build(BuildContext context) {
    final w = style.px(256);
    final h = style.px(144);
    Widget placeholder(IconData icon, Color color) => Container(
      width: w,
      height: h,
      color: AppPalette.inkRaised1,
      child: Icon(icon, color: color, size: style.px(48)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(style.px(8)),
      child: marker.still
          ? Image.network(
              api.stillUrl(marker.session, marker.i),
              width: w,
              height: h,
              fit: BoxFit.cover,
              // Stills are full resolution: decode them small.
              cacheWidth: (w * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, _, _) =>
                  placeholder(Icons.broken_image_rounded, DocStyle.muted),
            )
          : placeholder(Icons.hourglass_top_rounded, DocStyle.muted),
    );
  }
}
