/// An icon button for a clipboard copy: the copy glyph, a spinner while the
/// call runs, a check for 1.5 s on success, the error glyph on failure (until
/// the next tap). Icons only; the accessibility label is passed in.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:game_research/app/doc_style.dart';
import 'package:material_ui/material_ui.dart';

enum _Phase { idle, busy, done, failed }

/// Runs [onCopy] on tap and shows how it went.
class CopyIcon extends StatefulWidget {
  /// A [size] logical px button labelled [semantic]; [onCopy] null disables it.
  const new({
    required this.semantic,
    required this.onCopy,
    required this.size,
    this.glyph = Icons.content_copy_rounded,
    this.color = DocStyle.body,
    this.hold = const Duration(milliseconds: 1500),
    super.key,
  });

  /// Accessibility label (every state keeps it).
  final String semantic;

  /// The copy; throwing marks the failure. Null = disabled.
  final Future<void> Function()? onCopy;

  /// Icon size in logical px.
  final double size;

  /// The idle glyph (a files copy and a text copy differ).
  final IconData glyph;

  /// Colour of the idle glyph.
  final Color color;

  /// How long the check stays.
  final Duration hold;

  @override
  State<CopyIcon> createState() => _CopyIconState();
}

class _CopyIconState extends State<CopyIcon> {
  _Phase _phase = _Phase.idle;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _phase = _Phase.busy);
    var next = _Phase.done;
    try {
      await widget.onCopy!();
    } on Exception {
      next = _Phase.failed;
    }
    if (!mounted) return;
    setState(() => _phase = next);
    if (next == _Phase.done) {
      _reset = Timer(widget.hold, () {
        if (mounted) setState(() => _phase = _Phase.idle);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final semantic = widget.semantic;
    final size = widget.size;
    final idle = _phase == _Phase.idle || _phase == _Phase.failed;
    return IconButton(
      onPressed: idle && widget.onCopy != null ? _run : null,
      tooltip: 'Copy',
      color: widget.color,
      iconSize: size,
      icon: switch (_phase) {
        _Phase.busy => SizedBox.square(
          dimension: size * 0.7,
          child: CircularProgressIndicator(
            strokeWidth: size / 12,
            semanticsLabel: semantic,
          ),
        ),
        _Phase.done => Icon(
          Icons.check_rounded,
          color: AppPalette.success,
          semanticLabel: semantic,
        ),
        _Phase.failed => Icon(
          Icons.error_outline_rounded,
          color: AppPalette.danger,
          semanticLabel: semantic,
        ),
        _Phase.idle => Icon(widget.glyph, semanticLabel: semantic),
      },
    );
  }
}
