/// One message part of kuhy's notes as a card: a `n/of` header with the two
/// copy icons (stills, text), then a row per marker. Icons, numbers and the
/// notes kuhy typed himself; no labels.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_research/app/api.dart';
import 'package:game_research/app/copy_icon.dart';
import 'package:game_research/app/doc_style.dart';
import 'package:game_research/app/marker_style.dart';
import 'package:game_research/app/notes_models.dart';

const _tabular = [FontFeature.tabularFigures()];

/// A part of game [appid]'s notes.
class NotesCard extends StatelessWidget {
  /// Draws [part] at [style]; copies go through [api].
  const new({
    required this.api,
    required this.appid,
    required this.part,
    required this.style,
    super.key,
  });

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
    final size = style.px(56);
    final rows = <Widget>[];
    String? date;
    for (final m in part.markers) {
      if (m.date != date) {
        date = m.date;
        rows.add(_DateRow(date: date, style: style));
      }
      rows.add(_MarkerRow(api: api, marker: m, style: style));
    }
    return Container(
      width: style.px(1100),
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
                  fontSize: style.px(44),
                  color: DocStyle.heading,
                  fontFeatures: _tabular,
                ),
              ),
              const Spacer(),
              CopyIcon(
                semantic: 'copy notes ${part.n} files',
                glyph: Icons.photo_library_rounded,
                size: size,
                onCopy: part.hasStills
                    ? () => api.copyPart(appid, part.n, 'files')
                    : null,
              ),
              CopyIcon(
                semantic: 'copy notes ${part.n} text',
                glyph: Icons.text_snippet_rounded,
                size: size,
                onCopy: () => api.copyPart(appid, part.n, 'text'),
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
            size: style.px(36),
          ),
          SizedBox(width: style.px(16)),
          Text(
            date,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: style.px(36),
              color: DocStyle.muted,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkerRow extends StatelessWidget {
  const new({required this.api, required this.marker, required this.style});

  final ResearchApi api;
  final NoteMarker marker;
  final DocStyle style;

  @override
  Widget build(BuildContext context) {
    final look = kMarkerStyles.firstWhere(
      (s) => s.tag == marker.tag,
      orElse: () => kMarkerStyles.last,
    );
    final text = TextStyle(
      fontFamily: 'Inter',
      fontSize: style.px(36),
      color: DocStyle.body,
      fontFeatures: _tabular,
    );
    return SizedBox(
      height: style.px(150),
      child: Row(
        children: [
          Icon(look.icon, color: look.color, size: style.px(56)),
          SizedBox(width: style.px(20)),
          Text(marker.time, style: text),
          SizedBox(width: style.px(24)),
          Expanded(
            child: Text(
              marker.note,
              style: text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _Thumb(api: api, marker: marker, style: style),
          CopyIcon(
            semantic: 'copy marker ${marker.session} ${marker.i}',
            size: style.px(56),
            onCopy: marker.still
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
    final w = style.px(224);
    final h = style.px(126);
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
