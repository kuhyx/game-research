import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/slug.dart';

void main() {
  test('slugify lowercases and hyphenates', () {
    expect(
      slugify('Librarian: Tidy Up the Arcane Library'),
      'librarian-tidy-up-the-arcane-library',
    );
    expect(slugify('  --Café   Déjà!! '), 'caf-d-j');
    expect(slugify('???'), 'game');
  });

  test('slugify caps the length without a trailing hyphen', () {
    final s = slugify('${'a' * 30} ${'b' * 40}');
    expect(s.length, lessThanOrEqualTo(48));
    expect(s.endsWith('-'), isFalse);
  });

  test('sessionId is a sortable stamp plus the slug', () {
    final id = sessionId(DateTime(2026, 11, 11, 9, 5, 7), 'foo-game');
    expect(id, '20261111-090507-foo-game');
  });
}
