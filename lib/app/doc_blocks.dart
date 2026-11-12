/// The reader's view of a research document: the markdown cut into blocks
/// (headings, bullets, paragraphs, run-in labelled bullets), with the
/// questions that are still open folded into one line of ids and the status
/// lines dropped.
library;

import 'package:game_research/core/doc_refs.dart';

/// What a block is, which decides its style and spacing.
enum BlockKind {
  /// `# `
  h1,

  /// `## `
  h2,

  /// `### ` (a question when it starts with `Q1.2`)
  h3,

  /// Consecutive plain lines.
  paragraph,

  /// `- ` item.
  bullet,

  /// `- **Answer:**`-style item: [DocBlock.label] then the text.
  label,

  /// The one line listing the ids of all open questions.
  openIds,
}

/// One block of a document.
class DocBlock {
  /// A block of [kind] with source [text] (inline markup still in it).
  const new(this.kind, this.text, {this.label = ''});

  /// What it is.
  final BlockKind kind;

  /// The text, inline markup unparsed.
  final String text;

  /// `Answer`, `Evidence`, `Status` or `For <repo>` for [BlockKind.label].
  final String label;

  /// A copy with more text (a wrapped source line).
  DocBlock appended(String more) => DocBlock(kind, '$text $more', label: label);
}

final _questionHead = RegExp(r'^(Q\d+(?:\.\d+)*)\b');
final _heading = RegExp(r'^(#{1,4}) +(.*)$');
final _bullet = RegExp(r'^\s*[-*] +(.*)$');
final _rule = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');

/// The blocks of [markdown], open questions collapsed.
List<DocBlock> parseDoc(String markdown) => _collapseOpen(_scan(markdown));

List<DocBlock> _scan(String markdown) {
  final out = <DocBlock>[];
  var inComment = false;
  var open = false; // last block can still take continuation lines
  for (final raw in markdown.split('\n')) {
    final line = raw.trimRight();
    if (inComment || line.trimLeft().startsWith('<!--')) {
      inComment = !line.contains('-->');
      continue;
    }
    if (line.trim().isEmpty || _rule.hasMatch(line)) {
      open = false;
      continue;
    }
    final head = _heading.firstMatch(line);
    if (head != null) {
      final level = head.group(1)!.length;
      final kind = level == 1
          ? BlockKind.h1
          : level == 2
          ? BlockKind.h2
          : BlockKind.h3;
      out.add(DocBlock(kind, head.group(2)!.trim()));
      open = false;
      continue;
    }
    final label = labelLine.firstMatch(line);
    if (label != null) {
      out.add(
        DocBlock(BlockKind.label, label.group(2)!, label: label.group(1)!),
      );
      open = true;
      continue;
    }
    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      out.add(DocBlock(BlockKind.bullet, bullet.group(1)!));
      open = true;
    } else if (open) {
      out.last = out.last.appended(line.trim());
    } else {
      out.add(DocBlock(BlockKind.paragraph, line.trim()));
      open = true;
    }
  }
  return out;
}

bool _isHeading(DocBlock b) =>
    b.kind == BlockKind.h1 || b.kind == BlockKind.h2 || b.kind == BlockKind.h3;

/// Drops every `Status` block, and every question whose status is `open`,
/// leaving one [BlockKind.openIds] block where the first of them was.
List<DocBlock> _collapseOpen(List<DocBlock> blocks) {
  final out = <DocBlock>[];
  final ids = <String>[];
  var idsAt = -1;
  var i = 0;
  while (i < blocks.length) {
    final b = blocks[i];
    final id = b.kind == BlockKind.h3 ? _questionHead.firstMatch(b.text) : null;
    var end = i + 1;
    while (end < blocks.length && !_isHeading(blocks[end])) {
      end++;
    }
    final section = blocks.sublist(i, end);
    final isOpen =
        id != null &&
        section.any((s) => s.label == 'Status' && s.text.trim() == 'open');
    if (isOpen) {
      if (idsAt < 0) idsAt = out.length;
      ids.add(id.group(1)!);
    } else {
      out.addAll(section.where((s) => s.label != 'Status'));
    }
    i = end;
  }
  if (idsAt >= 0) {
    out.insert(idsAt, DocBlock(BlockKind.openIds, ids.join(' · ')));
  }
  return out;
}
