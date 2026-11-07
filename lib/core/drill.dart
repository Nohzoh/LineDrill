import 'package:dartchess/dartchess.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import 'repertoire.dart';

/// Façon de réviser.
enum DrillMode {
  /// Sans chrono ; après une erreur, il faut rejouer le bon coup.
  learning('Apprentissage'),

  /// Chrono par coup, comme en bullet.
  reflex('Réflexe');

  const DrillMode(this.label);

  final String label;
}

/// Temps accordé par coup en mode réflexe.
const reflexLimit = Duration(seconds: 3);

/// Note FSRS d'une tentative.
///
/// Raté, indice ou temps dépassé en réflexe : à revoir vite. En réflexe,
/// un coup trouvé en moins de la moitié du temps est « facile ».
fsrs.Rating rateAttempt({
  required DrillMode mode,
  required bool correct,
  required Duration elapsed,
}) {
  if (!correct) return fsrs.Rating.again;
  if (mode == DrillMode.learning) return fsrs.Rating.good;
  if (elapsed > reflexLimit) return fsrs.Rating.again;
  if (elapsed * 2 <= reflexLimit) return fsrs.Rating.easy;
  return fsrs.Rating.good;
}

/// État de révision de chaque coup de référence, par identifiant d'entrée.
class DrillDeck {
  DrillDeck([Map<String, fsrs.Card> cards = const {}]) : _cards = Map.of(cards);

  final Map<String, fsrs.Card> _cards;

  static final _scheduler = fsrs.Scheduler(enableFuzzing: false);

  /// Carte d'une entrée ; une entrée jamais révisée est due tout de suite.
  fsrs.Card cardFor(String entryId, DateTime now) =>
      _cards[entryId] ?? fsrs.Card(cardId: entryId.hashCode, due: now.toUtc());

  bool isNew(String entryId) => !_cards.containsKey(entryId);

  /// Copie avec la révision de [entryId] notée [rating] à [now].
  DrillDeck rate(String entryId, fsrs.Rating rating, DateTime now) {
    final (:card, reviewLog: _) =
        _scheduler.reviewCard(cardFor(entryId, now), rating, reviewDateTime: now.toUtc());
    return DrillDeck({..._cards, entryId: card});
  }

  Map<String, Object?> toJson() => {for (final e in _cards.entries) e.key: e.value.toMap()};

  factory DrillDeck.fromJson(Map<String, Object?> json) => DrillDeck({
        for (final e in json.entries) e.key: _cardFromJson((e.value! as Map).cast<String, Object?>()),
      });

  /// Le JSON peut rendre `3.0` sous forme d'entier : on remet des doubles.
  static fsrs.Card _cardFromJson(Map<String, Object?> map) => fsrs.Card.fromMap({
        ...map,
        'stability': (map['stability'] as num?)?.toDouble(),
        'difficulty': (map['difficulty'] as num?)?.toDouble(),
      });
}

/// Entrées à réviser maintenant pour [color] : les plus en retard d'abord,
/// puis les nouvelles, celles que je rate le plus souvent dans mes parties
/// en tête ([missRate] : part des parties où je n'ai pas joué le coup).
List<RepertoireEntry> dueEntries(
  Repertoire repertoire,
  DrillDeck deck, {
  required Side color,
  required DateTime now,
  Map<String, double> missRate = const {},
  int limit = 20,
}) {
  final due = [
    for (final e in repertoire.entries)
      if (e.color == color && !deck.cardFor(e.id, now).due.isAfter(now.toUtc())) e,
  ];
  int compare(RepertoireEntry a, RepertoireEntry b) {
    final newA = deck.isNew(a.id), newB = deck.isNew(b.id);
    if (newA != newB) return newA ? 1 : -1;
    if (!newA) {
      final byDue = deck.cardFor(a.id, now).due.compareTo(deck.cardFor(b.id, now).due);
      if (byDue != 0) return byDue;
    }
    final byMiss = (missRate[b.id] ?? 0).compareTo(missRate[a.id] ?? 0);
    if (byMiss != 0) return byMiss;
    return a.line.length.compareTo(b.line.length);
  }

  due.sort(compare);
  return due.take(limit).toList();
}

/// Prochaine révision prévue pour [color] après [now], ou `null`.
DateTime? nextDue(Repertoire repertoire, DrillDeck deck, {required Side color, required DateTime now}) {
  DateTime? next;
  for (final e in repertoire.entries) {
    if (e.color != color) continue;
    final due = deck.cardFor(e.id, now).due;
    if (due.isAfter(now.toUtc()) && (next == null || due.isBefore(next))) next = due;
  }
  return next;
}
