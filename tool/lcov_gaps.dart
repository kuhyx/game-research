/// Prints, per `lib/` file, line coverage and the uncovered line numbers of
/// one or more lcov files (merged by taking the best hit count per line).
///
/// `dart run tool/lcov_gaps.dart coverage/core.info coverage/desktop.info`
library;

import 'dart:io';

void main(List<String> args) {
  final hits = <String, Map<int, int>>{};
  for (final path in args) {
    String? file;
    for (final line in File(path).readAsLinesSync()) {
      if (line.startsWith('SF:')) {
        file = line.substring(3);
        hits.putIfAbsent(file, () => {});
      } else if (line.startsWith('DA:') && file != null) {
        final parts = line.substring(3).split(',');
        final n = int.parse(parts[0]);
        final h = int.parse(parts[1]);
        final map = hits[file]!;
        map[n] = (map[n] ?? 0) > h ? map[n]! : h;
      }
    }
  }
  var found = 0;
  var hit = 0;
  for (final e
      in hits.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    final missed = [
      for (final l in e.value.entries)
        if (l.value == 0) l.key,
    ]..sort();
    found += e.value.length;
    hit += e.value.length - missed.length;
    if (missed.isNotEmpty) {
      stdout.writeln(
        '${e.key}: ${e.value.length - missed.length}/${e.value.length} '
        'missing ${missed.join(',')}',
      );
    }
  }
  stdout.writeln('TOTAL $hit/$found lines');
}
