import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import 'game_record.dart';
import 'opening_tree.dart';
import 'openings.dart';
import 'repertoire.dart';
import 'training.dart';

/// Avis de Stockfish sur un de mes coups dans une position.
class HabitCheck {
  const HabitCheck(this.quality, {this.better});

  final MoveQuality quality;

  /// Meilleur coup du moteur, en SAN, quand ce n'est pas le coup jugé.
  final String? better;

  /// Erreur ou gaffe : le coup est à remplacer. Une imprécision reste jouable.
  bool get isError => quality == MoveQuality.mistake || quality == MoveQuality.blunder;

  Map<String, Object?> toJson() => {'quality': quality.name, if (better != null) 'better': better};

  /// `null` si l'avis est illisible (qualité inconnue).
  static HabitCheck? fromJson(Map<String, Object?> json) {
    final quality = MoveQuality.values.asNameMap()[json['quality']];
    final better = json['better'];
    return quality == null ? null : HabitCheck(quality, better: better is String ? better : null);
  }
}

/// Clé d'un avis : la position (clé `positionKey`) et le coup en SAN.
String habitCheckKey(String positionKey, String san) => '$positionKey|$san';

/// Un de mes coups que Stockfish n'a pas encore jugé.
class UncheckedHabit {
  const UncheckedHabit(this.node, this.move);

  final PositionNode node;
  final MoveStats move;

  String get key => habitCheckKey(node.key, move.san);
}

/// Ce que mes parties disent d'un de mes coups dans une variante.
enum HabitStatus {
  /// Je joue presque toujours le même coup, et c'est celui à retenir.
  known,

  /// Aucun coup ne domine dans mes parties.
  hesitant,

  /// Mon répertoire prévoit un autre coup que celui que je joue le plus.
  offRepertoire,

  /// Stockfish juge mon coup habituel mauvais : un autre coup est à retenir.
  toFix,
}

/// Une position d'une variante où c'est à moi de jouer.
class HabitStep {
  const HabitStep({
    required this.node,
    required this.line,
    required this.reached,
    required this.played,
    required this.alternative,
    required this.reference,
    required this.status,
    this.check,
  });

  final PositionNode node;

  /// Coups depuis la position initiale jusqu'à cette position.
  final List<String> line;

  /// Parties qui continuent depuis cette position.
  final int reached;

  /// Mon coup le plus joué ici.
  final MoveStats played;

  /// Mon autre coup le plus joué, s'il y en a un.
  final MoveStats? alternative;

  /// Coup à retenir, en SAN : celui du répertoire, sinon mon coup habituel,
  /// remplacé si Stockfish le juge mauvais.
  final String reference;

  final HabitStatus status;

  /// Avis de Stockfish sur [played], s'il a été demandé.
  final HabitCheck? check;

  /// Part des parties où j'ai joué [played].
  double get share => played.count / reached;
}

/// Une suite de coups que mes adversaires me font jouer assez souvent.
class OpeningVariant {
  OpeningVariant({required this.line, required this.name, required this.games, required this.steps});

  /// Coups de la variante depuis la position initiale.
  final List<String> line;

  /// Nom de la position nommée la plus profonde de la variante.
  final OpeningName? name;

  /// Parties arrivées au bout de [line], quel que soit l'ordre des coups.
  final List<GameRecord> games;

  /// Mes coups dans la variante, dans l'ordre.
  final List<HabitStep> steps;

  int get count => games.length;

  late final double score = meanScore(games);

  /// Nombre de mes coups acquis d'affilée depuis le début.
  int get knownDepth => steps.takeWhile((s) => s.status == HabitStatus.known).length;

  /// Premier coup qui n'est pas acquis, ou `null` si tous le sont.
  HabitStep? get gap => steps.where((s) => s.status != HabitStatus.known).firstOrNull;
}

/// Les variantes d'une même ouverture (« Scandinavian Defense »).
class OpeningFamily {
  OpeningFamily(this.name, this.variants, this.games);

  final String name;

  /// De la plus jouée à la moins jouée.
  final List<OpeningVariant> variants;

  /// Parties de l'ouverture : celles de ses variantes, et celles qui les
  /// quittent en route (réponse adverse rare, autre coup de ma part).
  final List<GameRecord> games;

  int get count => games.length;

  late final double score = meanScore(games);
}

/// Mes ouvertures, de la plus jouée à la moins jouée.
class OpeningReport {
  const OpeningReport(this.families, this.minGames, {this.steps = const [], this.unchecked = const []});

  final List<OpeningFamily> families;

  /// Nombre de parties à partir duquel une réponse adverse fait une variante.
  final int minGames;

  /// Les positions où mon répertoire me mène, une fois chacune : celles du
  /// bilan atteintes en ne suivant que des coups à retenir. Les variantes
  /// montrent aussi ce que je joue sous un coup à abandonner ; pas cette liste.
  final List<HabitStep> steps;

  /// Mes coups qui attendent l'avis de Stockfish. Tant qu'il en reste, les
  /// coups à retenir sont provisoires et [steps] s'arrête à eux : rien n'est
  /// demandé sous un coup qui peut encore être remplacé.
  final List<UncheckedHabit> unchecked;
}

/// Coups de référence à ajouter au [repertoire] : le coup à retenir de chaque
/// position de [OpeningReport.steps] (bilan de [color]) qui n'en a pas encore.
List<RepertoireEntry> habitEntries(OpeningReport report, Side color, Repertoire repertoire) => [
      for (final step in report.steps)
        if (repertoire.lookup(color, step.node.key) == null)
          RepertoireEntry(
            color: color,
            positionKey: step.node.key,
            san: step.reference,
            line: List.unmodifiable(step.line),
          ),
    ];

/// Famille des variantes qu'aucune position nommée ne traverse.
const unnamedFamily = 'Autres lignes';

/// Part des parties à partir de laquelle un coup est une habitude.
const habitShare = 0.6;

/// Seuil de parties d'une variante : 10 comme pour les lignes faibles, moins
/// quand il y a peu de parties (5 au minimum) pour qu'un bilan reste possible
/// après un premier import.
int habitMinGames(int games) => (games / 60).round().clamp(5, 10);

/// Bilan de mes ouvertures avec [color] : ce que je joue, variante par
/// variante, et jusqu'où mes coups sont une habitude.
///
/// Depuis la position initiale, chaque réponse adverse vue dans au moins
/// [minGames] parties ouvre une branche, et de mon côté un seul coup est
/// suivi : celui du [repertoire] si je le joue dans au moins [minGames]
/// parties, sinon mon coup le plus joué, pour que le bilan reste celui de
/// mes parties. Une variante s'arrête quand les parties deviennent trop
/// rares ; deux ordres de coups qui se rejoignent ne font qu'une variante,
/// celle du chemin le plus joué.
///
/// Un de mes coups est acquis s'il est joué dans au moins [habitShare] des
/// parties (au pour cent près, comme à l'affichage) et s'accorde avec le
/// répertoire. Chaque partie compte dans une seule ouverture : celle de la
/// position la plus profonde de son chemin que le parcours a traversée.
///
/// Là où le répertoire ne dit rien, [checks] (avis de Stockfish, par
/// [habitCheckKey]) corrige mes habitudes : le coup à retenir est le premier
/// de mes coups réguliers, du plus joué au moins joué, qui ne soit ni une
/// erreur ni une gaffe ; à défaut, le meilleur coup du moteur. Sous un coup
/// à retenir que je ne joue pas assez pour être suivi, la variante reste
/// celle de mes parties mais sort du répertoire : ses positions ne sont ni
/// vérifiées ni proposées ([OpeningReport.steps]).
OpeningReport openingReport(
  OpeningTree tree, {
  required Side color,
  OpeningBook book = OpeningBook.empty,
  Repertoire? repertoire,
  Map<String, HabitCheck> checks = const {},
  int? minGames,
}) {
  final threshold = math.max(1, minGames ?? habitMinGames(tree.games.length));

  // Ouverture de chaque position traversée, et variante retenue pour chaque
  // position d'arrivée.
  final familyAt = <String, String?>{};
  final found = <String, ({List<String> line, OpeningName? name, List<HabitStep> steps, int flow})>{};
  final stepAt = <String, ({HabitStep step, int flow})>{};
  final unchecked = <String, UncheckedHabit>{};

  // [flow] : le coup le moins joué du chemin, qui départage deux ordres de
  // coups vers la même position. [path] : positions déjà traversées, une
  // répétition de coups ne doit pas faire tourner en rond. [onBook] : le
  // chemin n'a suivi que des coups à retenir, la position est donc de
  // celles où mon répertoire me mène, pour ce qui en est déjà vérifié.
  void walk(
    PositionNode node,
    List<String> line,
    List<HabitStep> steps,
    OpeningName? name,
    Set<String> path,
    int flow,
    bool onBook,
  ) {
    name = book.nameOf(node.key) ?? name;
    familyAt.putIfAbsent(node.key, () => name?.family);
    void end(List<HabitStep> steps) {
      if (line.isEmpty) return;
      final known = found[node.key];
      if (known != null && known.flow >= flow) return;
      found[node.key] = (line: line, name: name, steps: steps, flow: flow);
      familyAt[node.key] = name?.family;
    }

    final moves = node.moves;
    if (node.position.turn != color) {
      final replies = moves.where((m) => m.count >= threshold && !path.contains(m.childKey)).toList();
      if (replies.isEmpty) return end(steps);
      for (final reply in replies) {
        walk(
          tree.node(reply.childKey)!,
          [...line, reply.san],
          steps,
          name,
          {...path, reply.childKey},
          math.min(flow, reply.count),
          onBook,
        );
      }
      return;
    }

    final reached = moves.fold<int>(0, (sum, m) => sum + m.count);
    if (reached < threshold) return end(steps);
    final star = repertoire?.lookup(color, node.key)?.san;
    // À égalité de parties, le coup du répertoire est mon coup habituel.
    final starred = star == null ? null : node.move(star);
    final played = starred != null && starred.count == moves.first.count ? starred : moves.first;
    var reference = star;
    // Tant qu'un avis manque, le coup à retenir peut encore changer.
    var settled = true;
    if (reference == null && onBook) {
      for (final move in moves.take(3)) {
        // Moins d'une partie sur cinq : pas une habitude à garder.
        if (move != played && move.count * 5 < reached) break;
        final key = habitCheckKey(node.key, move.san);
        final check = checks[key];
        if (check == null) {
          unchecked.putIfAbsent(key, () => UncheckedHabit(node, move));
          settled = false;
        }
        if (check == null || !check.isError) {
          reference = move.san;
          break;
        }
      }
      reference ??= checks[habitCheckKey(node.key, played.san)]?.better;
    }
    reference ??= played.san;
    final step = HabitStep(
      node: node,
      line: line,
      reached: reached,
      played: played,
      alternative: moves.where((m) => m != played).firstOrNull,
      reference: reference,
      status: reference != played.san
          ? (star == null ? HabitStatus.toFix : HabitStatus.offRepertoire)
          : (played.count * 100 / reached).round() < (habitShare * 100).round()
              ? HabitStatus.hesitant
              : HabitStatus.known,
      check: onBook ? checks[habitCheckKey(node.key, played.san)] : null,
    );
    // Comme pour les variantes, le chemin le plus joué donne sa ligne.
    if (onBook && (stepAt[node.key]?.flow ?? -1) < flow) stepAt[node.key] = (step: step, flow: flow);
    // Un coup à retenir que je ne joue presque jamais ne doit pas cacher
    // les ouvertures que je joue vraiment en dessous.
    final kept = node.move(reference);
    final next = kept != null && kept.count >= threshold ? kept : played;
    if (path.contains(next.childKey)) return end([...steps, step]);
    walk(
      tree.node(next.childKey)!,
      [...line, next.san],
      [...steps, step],
      name,
      {...path, next.childKey},
      math.min(flow, next.count),
      onBook && settled && next == kept,
    );
  }

  walk(tree.root, const [], const [], null, {tree.rootKey}, tree.games.length, true);

  // Un seul passage sur les parties : celles de chaque variante (arrivées au
  // bout de sa ligne) et celles de chaque ouverture.
  final gamesAt = {for (final key in found.keys) key: <GameRecord>[]};
  final gamesOf = <String, List<GameRecord>>{};
  for (final game in tree.games) {
    var node = tree.root;
    var family = familyAt[tree.rootKey];
    for (final san in game.sans) {
      final move = node.move(san);
      if (move == null) break;
      if (familyAt.containsKey(move.childKey)) family = familyAt[move.childKey];
      // Une partie qui répète une position n'y compte qu'une fois.
      final arrived = gamesAt[move.childKey];
      if (arrived != null && (arrived.isEmpty || !identical(arrived.last, game))) arrived.add(game);
      node = tree.node(move.childKey)!;
    }
    gamesOf.putIfAbsent(family ?? unnamedFamily, () => []).add(game);
  }

  final byFamily = <String, List<OpeningVariant>>{};
  for (final MapEntry(:key, value: (:line, :name, :steps, flow: _)) in found.entries) {
    byFamily
        .putIfAbsent(name?.family ?? unnamedFamily, () => [])
        .add(OpeningVariant(line: line, name: name, games: gamesAt[key]!, steps: steps));
  }
  final families = [
    for (final entry in byFamily.entries)
      OpeningFamily(
        entry.key,
        entry.value..sort((a, b) => b.count.compareTo(a.count)),
        gamesOf[entry.key] ?? const [],
      ),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return OpeningReport(
    families,
    threshold,
    steps: [for (final (:step, flow: _) in stepAt.values) step],
    unchecked: unchecked.values.toList(),
  );
}
