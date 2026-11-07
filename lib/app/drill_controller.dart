import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../core/drill.dart';
import '../core/opening_tree.dart';
import '../core/repertoire.dart';
import 'providers.dart';

/// Horloge (remplaçable en test).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// État des révisions, enregistré à chaque note.
class DeckNotifier extends AsyncNotifier<DrillDeck> {
  @override
  Future<DrillDeck> build() async => (await ref.watch(repertoireStoreProvider.future)).loadDeck();

  Future<void> rate(String entryId, fsrs.Rating rating) async {
    final next = (await future).rate(entryId, rating, ref.read(clockProvider)());
    state = AsyncData(next);
    await (await ref.read(repertoireStoreProvider.future)).saveDeck(next);
  }
}

final deckProvider = AsyncNotifierProvider<DeckNotifier, DrillDeck>(DeckNotifier.new);

/// Part des parties où je n'ai pas joué mon coup de référence, par entrée.
final missRateProvider = Provider<Map<String, double>>((ref) {
  final usage = ref.watch(repertoireUsageProvider);
  return {
    for (final u in usage.values)
      if (u.reached > 0) u.entry.id: u.deviated.length / u.reached,
  };
});

/// Entrées à réviser maintenant pour la couleur filtrée.
final dueProvider = Provider<List<RepertoireEntry>>((ref) {
  final repertoire = ref.watch(repertoireProvider).value;
  final deck = ref.watch(deckProvider).value;
  if (repertoire == null || deck == null) return const [];
  return dueEntries(
    repertoire,
    deck,
    color: ref.watch(filterProvider).color,
    now: ref.watch(clockProvider)(),
    missRate: ref.watch(missRateProvider),
  );
});

enum DrillFeedback {
  none,
  correct,

  /// Raté : le bon coup est montré.
  wrong,

  /// Temps écoulé en mode réflexe.
  timeout,
}

/// Une question : trouver mon coup dans la position atteinte par [entry].
class DrillCard {
  const DrillCard(this.entry, this.position, this.lastMove);

  final RepertoireEntry entry;
  final Position position;
  final Move? lastMove;
}

class DrillState {
  const DrillState({
    this.active = false,
    this.mode = DrillMode.learning,
    this.color = Side.white,
    this.cards = const [],
    this.index = 0,
    this.shownAt,
    this.feedback = DrillFeedback.none,
    this.played,
    this.missed = false,
    this.correct = 0,
    this.wrong = 0,
  });

  final bool active;
  final DrillMode mode;
  final Side color;
  final List<DrillCard> cards;
  final int index;

  /// Moment où la question courante est apparue (chrono réflexe).
  final DateTime? shownAt;

  final DrillFeedback feedback;

  /// Coup joué sur la question courante, affiché sur l'échiquier.
  final Move? played;

  /// La question courante a déjà été ratée (en apprentissage, il faut
  /// ensuite rejouer le bon coup, sans nouvelle note).
  final bool missed;

  final int correct;
  final int wrong;

  bool get finished => active && index >= cards.length;

  DrillCard? get card => active && index < cards.length ? cards[index] : null;

  /// J'ai la main sur l'échiquier.
  bool get canPlay {
    if (card == null) return false;
    if (feedback == DrillFeedback.none) return true;
    return mode == DrillMode.learning && feedback == DrillFeedback.wrong;
  }

  /// Position affichée : la question, ou la question + mon coup juste.
  Position? get position {
    final c = card;
    if (c == null) return null;
    final move = played;
    return feedback == DrillFeedback.correct && move != null ? c.position.play(move) : c.position;
  }

  DrillState copyWith({
    int? index,
    DateTime? shownAt,
    DrillFeedback? feedback,
    Move? Function()? played,
    bool? missed,
    int? correct,
    int? wrong,
  }) =>
      DrillState(
        active: active,
        mode: mode,
        color: color,
        cards: cards,
        index: index ?? this.index,
        shownAt: shownAt ?? this.shownAt,
        feedback: feedback ?? this.feedback,
        played: played != null ? played() : this.played,
        missed: missed ?? this.missed,
        correct: correct ?? this.correct,
        wrong: wrong ?? this.wrong,
      );
}

class DrillController extends Notifier<DrillState> {
  @override
  DrillState build() => const DrillState();

  DateTime _now() => ref.read(clockProvider)();

  /// Démarre une séance sur les entrées dues de [color].
  Future<void> start(DrillMode mode, Side color) async {
    await ref.read(deckProvider.future);
    await ref.read(repertoireProvider.future);
    final entries = ref.read(dueProvider);
    final cards = <DrillCard>[];
    for (final entry in entries.where((e) => e.color == color)) {
      final card = _cardFor(entry);
      if (card != null) cards.add(card);
    }
    state = DrillState(active: true, mode: mode, color: color, cards: cards, shownAt: _now());
  }

  /// Rejoue la ligne de l'entrée ; `null` si elle ne mène plus à la position.
  static DrillCard? _cardFor(RepertoireEntry entry) {
    Position position = Chess.initial;
    Move? last;
    for (final san in entry.line) {
      final move = position.parseSan(san);
      if (move == null) return null;
      position = position.play(move);
      last = move;
    }
    if (positionKey(position) != entry.positionKey || position.parseSan(entry.san) == null) return null;
    return DrillCard(entry, position, last);
  }

  /// Mon coup sur la question courante.
  Future<void> attempt(Move move) async {
    final card = state.card;
    if (card == null || !state.canPlay) return;
    if (!card.position.isLegal(move)) return;
    final normalized = move is NormalMove ? card.position.normalizeMove(move) : move;
    final san = card.position.makeSan(normalized).$2;
    final correct = san == card.entry.san;

    if (correct) {
      state = state.copyWith(
        feedback: DrillFeedback.correct,
        played: () => normalized,
        correct: state.missed ? state.correct : state.correct + 1,
      );
      if (!state.missed) await _rate(card, correct: true);
      return;
    }
    if (state.missed) return; // déjà noté : on attend le bon coup.
    state = state.copyWith(
      feedback: DrillFeedback.wrong,
      played: () => null,
      missed: true,
      wrong: state.wrong + 1,
    );
    await _rate(card, correct: false);
  }

  /// Temps écoulé en mode réflexe sans coup joué.
  Future<void> timeout() async {
    final card = state.card;
    if (card == null || state.mode != DrillMode.reflex || state.feedback != DrillFeedback.none) return;
    state = state.copyWith(feedback: DrillFeedback.timeout, missed: true, wrong: state.wrong + 1);
    await _rate(card, correct: false);
  }

  /// Question suivante.
  void next() {
    if (state.card == null) return;
    state = DrillState(
      active: true,
      mode: state.mode,
      color: state.color,
      cards: state.cards,
      index: state.index + 1,
      shownAt: _now(),
      correct: state.correct,
      wrong: state.wrong,
    );
  }

  void stop() => state = const DrillState();

  Future<void> _rate(DrillCard card, {required bool correct}) {
    final elapsed = _now().difference(state.shownAt ?? _now());
    final rating = rateAttempt(mode: state.mode, correct: correct, elapsed: elapsed);
    return ref.read(deckProvider.notifier).rate(card.entry.id, rating);
  }
}

final drillProvider = NotifierProvider<DrillController, DrillState>(DrillController.new);
