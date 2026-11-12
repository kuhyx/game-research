/// The one visible word under each session-row stat, and the compact token
/// count.
///
/// kuhy, 2026-11-12: "in this case I want one word text" (CLAUDE.md textgate
/// exception). Every word is in [kStatWords]; nothing else on a row is text.
library;

/// Stat key -> the word shown under it.
const kStatWords = {
  'tokens': 'tokens',
  'cost': 'cost',
  'scan': 'scan',
  'captions': 'captions',
  'draft': 'draft',
};

/// [n] as `950`, `1.2k`, `950k`, `1.8M`, `12M`.
String compactTokens(int n) {
  String scaled(double v, String unit) {
    final s = v < 10 ? v.toStringAsFixed(1) : v.round().toString();
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}$unit';
  }

  if (n < 1000) return '$n';
  if (n < 999500) return scaled(n / 1000, 'k');
  return scaled(n / 1e6, 'M');
}
