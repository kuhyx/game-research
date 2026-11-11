/// File-name slugs for games and session folders.
library;

const _maxSlug = 48;

/// Lowercase ASCII words joined by `-`, at most 48 chars; `game` if empty.
String slugify(String name) {
  final words = name
      .toLowerCase()
      .split(RegExp('[^a-z0-9]+'))
      .where((w) => w.isNotEmpty);
  var slug = words.join('-');
  if (slug.length > _maxSlug) {
    slug = slug.substring(0, _maxSlug).replaceAll(RegExp(r'-+$'), '');
  }
  return slug.isEmpty ? 'game' : slug;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// `YYYYMMDD-HHMMSS-<slug>`: sorts by start time, readable in a file list.
String sessionId(DateTime start, String slug) =>
    '${start.year}${_two(start.month)}${_two(start.day)}-'
    '${_two(start.hour)}${_two(start.minute)}${_two(start.second)}-$slug';
