import 'dart:convert';
import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:linedrill/core/drill.dart';
import 'package:linedrill/core/repertoire.dart';
import 'package:linedrill/data/repertoire_store.dart';

RepertoireEntry _e(String line, String san, {Side color = Side.white}) => RepertoireEntry(
      color: color,
      positionKey: 'pos:$line',
      san: san,
      line: line.isEmpty ? const [] : line.split(' '),
    );

void main() {
  final now = DateTime.utc(2026, 11, 7, 12);

  test('notation des tentatives', () {
    expect(rateAttempt(mode: DrillMode.learning, correct: false, elapsed: Duration.zero), fsrs.Rating.again);
    expect(rateAttempt(mode: DrillMode.learning, correct: true, elapsed: const Duration(seconds: 30)),
        fsrs.Rating.good);
    expect(rateAttempt(mode: DrillMode.reflex, correct: true, elapsed: const Duration(milliseconds: 900)),
        fsrs.Rating.easy);
    expect(rateAttempt(mode: DrillMode.reflex, correct: true, elapsed: const Duration(seconds: 2)),
        fsrs.Rating.good);
    expect(rateAttempt(mode: DrillMode.reflex, correct: true, elapsed: const Duration(seconds: 4)),
        fsrs.Rating.again);
  });

  test('une entrée réussie n\'est plus due, une ratée revient vite', () {
    final ok = _e('e4 g6', 'd4');
    final miss = _e('e4 c6', 'd4');
    final rep = Repertoire([ok, miss]);
    var deck = DrillDeck();
    expect(dueEntries(rep, deck, color: Side.white, now: now), hasLength(2));

    deck = deck.rate(ok.id, fsrs.Rating.good, now).rate(miss.id, fsrs.Rating.again, now);
    final later = now.add(const Duration(minutes: 5));
    expect(dueEntries(rep, deck, color: Side.white, now: later).map((e) => e.id), [miss.id]);
    expect(deck.cardFor(ok.id, now).due.isAfter(later), isTrue);

    // Après plusieurs réussites, l'intervalle s'allonge au-delà d'un jour.
    var t = now;
    for (var i = 0; i < 4; i++) {
      t = deck.cardFor(ok.id, t).due;
      deck = deck.rate(ok.id, fsrs.Rating.good, t);
    }
    expect(deck.cardFor(ok.id, t).due.difference(t).inDays, greaterThanOrEqualTo(1));
  });

  test('ordre : en retard, puis nouvelles, les plus ratées d\'abord', () {
    final a = _e('e4 g6', 'd4'), b = _e('e4 c6', 'd4'), c = _e('e4 e5', 'Nf3'), black = _e('e4', 'd5', color: Side.black);
    final rep = Repertoire([a, b, c, black]);
    final earlier = now.subtract(const Duration(days: 3));
    final deck = DrillDeck().rate(c.id, fsrs.Rating.again, earlier);
    final due = dueEntries(rep, deck, color: Side.white, now: now, missRate: {b.id: 0.6, a.id: 0.1});
    expect(due.map((e) => e.san), ['Nf3', 'd4', 'd4']);
    expect(due[1].id, b.id);
    expect(dueEntries(rep, deck, color: Side.white, now: now, limit: 1), hasLength(1));
    expect(nextDue(rep, deck, color: Side.white, now: earlier), isNotNull);
  });

  test('stockage et JSON aux nombres entiers', () async {
    final tmp = await Directory.systemTemp.createTemp('linedrill');
    addTearDown(() => tmp.delete(recursive: true));
    final store = RepertoireStore(tmp);
    expect((await store.loadDeck()).isNew('x'), isTrue);
    final deck = DrillDeck().rate('x', fsrs.Rating.good, now);
    await store.saveDeck(deck);
    final back = await store.loadDeck();
    expect(back.isNew('x'), isFalse);
    expect(back.cardFor('x', now).due, deck.cardFor('x', now).due);

    final json = deck.toJson();
    final card = (json['x']! as Map).cast<String, Object?>();
    final withInts = {'x': {...card, 'stability': 3, 'difficulty': 5}};
    expect(DrillDeck.fromJson(jsonDecode(jsonEncode(withInts)) as Map<String, Object?>).cardFor('x', now).stability, 3.0);
  });
}
