/// How each marker kind looks: its icon and its flash colour.
library;

import 'package:flutter/material.dart';

/// One marker kind's look.
class MarkerStyle {
  /// Creates a style.
  const new(this.tag, this.icon, this.color);

  /// Tag name (`good`, ...).
  final String tag;

  /// Icon.
  final IconData icon;

  /// Colour, the same as the border flash (`MarkerTag.flashHex`).
  final Color color;
}

/// good, bad, confusing, note: green, red, yellow, blue (kuhy's colours).
const kMarkerStyles = [
  MarkerStyle('good', Icons.thumb_up_rounded, Color(0xFF3CB043)),
  MarkerStyle('bad', Icons.thumb_down_rounded, Color(0xFFE2302F)),
  MarkerStyle('confusing', Icons.question_mark_rounded, Color(0xFFF0C020)),
  MarkerStyle('note', Icons.edit_note_rounded, Color(0xFF2F6FE2)),
];
