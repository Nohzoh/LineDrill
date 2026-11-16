import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import 'game_record.dart';
import 'opening_tree.dart';
import 'openings.dart';
import 'repertoire.dart';

/// Ce que mes parties disent d'un de mes coups dans une variante.
enum HabitStatus {
  /// Je joue presque toujours le même coup, et c'est celui à retenir.
  known,

  /// Aucun coup ne domine dans mes parties.
  hesitant,

  /// Mon répertoire prévoit un autre coup que celui que je joue le plus.
  offRepertoire,
}

/// Une position d'une variante où c'est à moi de jouer.
class HabitStep {
  const HabitStep({
    required this.line,
    required this.reached,
    required this.played,
    required this.alternative,
    required this.reference,
    required this.status,
  });

  /// Coups depuis la position initiale jusqu'à cette position.
  final List<String> line;

  /// Parties qui continuent depuis cette position.
  final int reached;

  /// Mon coup le plus joué ici.
  final MoveStats played;

  /// Mon autre coup le plus joué, s'il y en a un.
  final MoveStats? alternative;

  /// Coup à retenir, en SAN : celui du répertoire, sinon mon coup habituel.
  final String reference;

  final HabitStatus status;

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
  const OpeningReport(this.families, this.minGames);

  final List<OpeningFamily> families;

  /// Nombre de parties à partir duquel une réponse adverse fait une variante.
  final int minGames;
}

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
OpeningReport openingReport(
  OpeningTree tree, {
  required Side color,
  OpeningBook book = OpeningBook.empty,
  Repertoire? repertoire,
  int? minGames,
}) {
  final threshold = math.max(1, minGames ?? habitMinGames(tree.games.length));

  // Ouverture de chaque position traversée, et variante retenue pour chaque
  // position d'arrivée.
  final familyAt = <String, String?>{};
  final found = <String, ({List<String> line, OpeningName? name, List<HabitStep> steps, int flow})>{};

  // [flow] : le coup le moins joué du chemin, qui départage deux ordres de
  // coups vers la même position. [path] : positions déjà traversées, une
  // répétition de coups ne doit pas faire tourner en rond.
  void walk(
    PositionNode node,
    List<String> line,
    List<HabitStep> steps,
    OpeningName? name,
    Set<String> path,
    int flow,
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
    final reference = star ?? played.san;
    final step = HabitStep(
      line: line,
      reached: reached,
      played: played,
      alternative: moves.where((m) => m != played).firstOrNull,
      reference: reference,
      status: reference != played.san
          ? HabitStatus.offRepertoire
          : (played.count * 100 / reached).round() < (habitShare * 100).round()
              ? HabitStatus.hesitant
              : HabitStatus.known,
    );
    // Un coup du répertoire que je ne joue presque jamais ne doit pas
    // cacher les ouvertures que je joue vraiment en dessous.
    final next = starred != null && starred.count >= threshold ? starred : played;
    if (path.contains(next.childKey)) return end([...steps, step]);
    walk(
      tree.node(next.childKey)!,
      [...line, next.san],
      [...steps, step],
      name,
      {...path, next.childKey},
      math.min(flow, next.count),
    );
  }

  walk(tree.root, const [], const [], null, {tree.rootKey}, tree.games.length);

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
  return OpeningReport(families, threshold);
}
