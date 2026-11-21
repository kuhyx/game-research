import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/core/research_game.dart';

void main() {
  group('ResearchApproval', () {
    test('round-trips', () {
      const a = ResearchApproval(7, addedAt: 1.5, flags: ['/h/a.pid']);
      final back = ResearchApproval.parse(jsonEncode(a.toJson()))!;
      expect(back.appid, 7);
      expect(back.addedAt, 1.5);
      expect(back.flags, ['/h/a.pid']);
    });

    for (final bad in ['', '{', '[]', '{"app_id":"7"}', '{"app_id":0}']) {
      test('rejects $bad', () => expect(ResearchApproval.parse(bad), isNull));
    }
  });

  group('tileLock', () {
    TileLock lock(int id, {bool installed = false, int? research}) => tileLock(
      appid: id,
      installed: installed,
      allowed: const {5},
      research: research,
    );

    test('installed or allowed games are open', () {
      expect(lock(1, installed: true), TileLock.open);
      expect(lock(5), TileLock.open);
    });
    test('others are blocked while the slot is free', () {
      expect(lock(2), TileLock.blocked);
    });
    test('the research game is marked, others show the slot taken', () {
      expect(lock(2, research: 2), TileLock.research);
      expect(lock(2, installed: true, research: 2), TileLock.research);
      expect(lock(3, research: 2), TileLock.taken);
      expect(lock(1, installed: true, research: 2), TileLock.open);
    });
  });

  group('enforcer files', () {
    test('owned games', () {
      final text = jsonEncode({
        'games': [
          {'app_id': 10, 'name': 'A'},
          {'app_id': 'x', 'name': 'B'},
          {'name': 'C'},
          {'app_id': 11},
        ],
      });
      expect(ownedGames(text), {10: 'A', 11: ''});
      expect(ownedGames('nope'), isEmpty);
    });

    test('allowed ids: assignment, picks, exceptions, zero achievements', () {
      final ids = enforcerAllowed(
        state: jsonEncode({
          'current_app_id': 1,
          'manual_picks': [
            {'app_id': 2},
            {'x': 3},
          ],
        }),
        exceptions: jsonEncode([
          {'app_id': 4},
          'junk',
        ]),
        zeroAchievements: jsonEncode({
          'checked': {'6': 1.0, 'x': 2.0},
        }),
      );
      expect(ids, {1, 2, 4, 6});
      expect(
        enforcerAllowed(state: '', exceptions: '{', zeroAchievements: '[]'),
        isEmpty,
      );
    });
  });
}
