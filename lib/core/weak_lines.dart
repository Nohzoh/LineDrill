import 'opening_tree.dart';

/// Une ligne où l'utilisateur perd des points.
class WeakLine {
  WeakLine(this.line, this.stats, this.cost);

  /// Coups depuis la position initiale, en SAN ; le dernier est [stats].
  final List<String> line;

  final MoveStats stats;

  /// Points perdus par rapport au score moyen : (moyenne − score) × parties.
  final double cost;

  /// Vrai si le dernier coup est celui de l'adversaire : la question est
  /// alors « que jouer ici ? ». Sinon, c'est mon propre coup qui coûte.
  bool lastMoveIsOpponent(bool userIsWhite) => line.length.isOdd != userIsWhite;

  bool isAncestorOf(WeakLine other) =>
      other.line.length > line.length &&
      List.generate(line.length, (i) => other.line[i] == line[i]).every((same) => same);
}

/// Classe les lignes les plus coûteuses de [tree].
///
/// - Seuls les coups joués dans au moins [minGames] parties comptent.
/// - La référence est le score moyen de l'arbre (couleur et cadence
///   filtrées), pour que les coups très joués mais neutres, comme 1.e4,
///   ne remontent pas.
/// - Une ligne plus profonde qu'une ligne déjà retenue n'est gardée que si
///   son score est au moins [refineMargin] plus bas : elle précise alors
///   où le problème se situe. À l'inverse, une ligne plus courte n'est
///   gardée que si elle perd encore des points une fois retirées ses
///   sous-lignes retenues.
List<WeakLine> weakLines(
  OpeningTree tree, {
  int minGames = 10,
  int limit = 20,
  double refineMargin = 0.05,
}) {
  final baseline = tree.score;
  final candidates = <WeakLine>[];
  final seen = <String>{};

  // Parcours en largeur, coups fréquents d'abord : avec les transpositions,
  // chaque coup est rattaché à son chemin le plus joué.
  var frontier = [(tree.root, const <String>[], const <MoveStats>[])];
  while (frontier.isNotEmpty) {
    final next = <(PositionNode, List<String>, List<MoveStats>)>[];
    for (final (node, line, chain) in frontier) {
      for (final stats in node.moves) {
        if (stats.count < minGames) continue;
        if (!seen.add('${node.key}|${stats.san}')) continue;
        final path = [...line, stats.san];
        final pathStats = [...chain, stats];
        final cost = (baseline - stats.score) * stats.count;
        if (cost > 0) {
          // Raccourcit la ligne tant que le coup précédent couvre presque
          // les mêmes parties avec un score aussi mauvais : « 1.e4 g6 »
          // plutôt que « 1.e4 g6 2.Nf3 », joué dans 24 des 26 parties.
          var end = path.length;
          while (end > 1) {
            final prev = pathStats[end - 2];
            if (prev.count > stats.count * 1.25 || prev.score > stats.score + refineMargin) break;
            end--;
          }
          final kept = pathStats[end - 1];
          if (seen.add('line|${path.take(end).join(' ')}')) {
            candidates.add(WeakLine(
              path.sublist(0, end),
              kept,
              (baseline - kept.score) * kept.count,
            ));
          }
        }
        next.add((tree.node(stats.childKey)!, path, pathStats));
      }
    }
    frontier = next;
  }

  candidates.sort((a, b) => b.cost.compareTo(a.cost));
  final accepted = <WeakLine>[];
  for (final c in candidates) {
    // L'ancêtre retenu le plus proche.
    WeakLine? ancestor;
    for (final a in accepted) {
      if (a.isAncestorOf(c) && (ancestor == null || a.line.length > ancestor.line.length)) {
        ancestor = a;
      }
    }
    if (ancestor != null && c.stats.score > ancestor.stats.score - refineMargin) continue;
    // Coût des sous-lignes retenues les plus hautes (sans compter deux fois
    // une sous-ligne et sa propre sous-ligne).
    final descendants = accepted.where((a) => c.isAncestorOf(a)).toList();
    final descendantsCost = descendants
        .where((d) => !descendants.any((o) => o.isAncestorOf(d)))
        .fold<double>(0, (sum, a) => sum + a.cost);
    if (descendantsCost > 0 && c.cost - descendantsCost < 1) continue;
    accepted.add(c);
    if (accepted.length >= limit) break;
  }
  return accepted;
}
