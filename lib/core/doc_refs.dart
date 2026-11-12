/// What the research documents' writing rules and the reader share: the
/// evidence references (frame files, mm:ss offsets, session stamps) that the
/// word caps leave out and the reader sets muted in tabular figures, and the
/// run-in labels of a question's bullets.
library;

/// A frame file (`f_0013`), an offset (`07:26`, `1:02:03`) or a session
/// stamp (`20261111-185105`).
final refPattern = RegExp(
  r'\bf_\d+\b|\b\d{8}-\d{6}\b|\b\d{1,2}:\d{2}(?::\d{2})?\b',
);

/// A labelled bullet: group 1 the label (`Answer`, `Evidence`, `Status`,
/// `For <repo>`), group 2 the text after it.
final labelLine = RegExp(
  r'^- \*\*(Answer|Evidence|Status|For [^:*]+):\*\*\s*(.*)$',
  multiLine: true,
);

final _hasWordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Words of [text] that are prose: references and tokens without a letter
/// or digit (dashes, brackets) do not count.
int proseWords(String text) => text
    .replaceAll(refPattern, ' ')
    .split(RegExp(r'\s+'))
    .where(_hasWordChar.hasMatch)
    .length;
