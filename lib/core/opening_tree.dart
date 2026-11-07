import 'package:dartchess/dartchess.dart';

import 'game_record.dart';

/// Clé d'une position : les 4 premiers champs du FEN (sans compteurs de
/// coups), pour fusionner les transpositions.
String positionKey(Position position) => position.fen.split(' ').take(4).join(' ');

/// Filtre appliqué aux parties avant de construire l'arbre.
class GameFilter {
  const GameFilter({required this.color, this.timeClasses = const {}});

  /// Couleur jouée par l'utilisateur.
  final Side color;

  /// Cadences retenues ; vide = toutes.
  final Set<TimeClass> timeClasses;

  bool accepts(GameRecord game) =>
      game.color == color && (timeClasses.isEmpty || timeClasses.contains(game.timeClass));

  GameFilter copyWith({Side? color, Set<TimeClass>? timeClasses}) =>
      GameFilter(color: color ?? this.color, timeClasses: timeClasses ?? this.timeClasses);
}

/// Statistiques d'un coup joué depuis une position.
class MoveStats {
  MoveStats(this.san, this.move, this.childKey);

  final String san;
  final Move move;

  /// Position atteinte après le coup.
  final String childKey;

  final List<GameRecord> games = [];
  double points = 0;

  int get count => games.length;

  /// Score de l'utilisateur, entre 0 et 1.
  double get score => count == 0 ? 0 : points / count;
}

/// Une position de l'arbre et les coups joués depuis elle.
class PositionNode {
  PositionNode(this.key, this.position);

  final String key;
  final Position position;
  final Map<String, MoveStats> _moves = {};

  /// Coups joués depuis cette position, du plus fréquent au moins fréquent.
  List<MoveStats> get moves =>
      _moves.values.toList()..sort((a, b) => b.count.compareTo(a.count));

  MoveStats? move(String san) => _moves[san];
}

/// Arbre des ouvertures de l'utilisateur, positions indexées par [positionKey].
class OpeningTree {
  OpeningTree._(this.games, this._nodes, this.rootKey);

  /// Construit l'arbre à partir des parties acceptées par [filter].
  factory OpeningTree.build(Iterable<GameRecord> allGames, GameFilter filter) {
    final games = allGames.where(filter.accepts).toList();
    final root = Chess.initial;
    final rootKey = positionKey(root);
    final nodes = <String, PositionNode>{rootKey: PositionNode(rootKey, root)};

    for (final game in games) {
      var node = nodes[rootKey]!;
      for (final san in game.sans) {
        var stats = node.move(san);
        if (stats == null) {
          final move = node.position.parseSan(san);
          if (move == null) break;
          final next = node.position.play(move);
          final childKey = positionKey(next);
          nodes.putIfAbsent(childKey, () => PositionNode(childKey, next));
          stats = MoveStats(san, move, childKey);
          node._moves[san] = stats;
        }
        stats.games.add(game);
        stats.points += game.score;
        node = nodes[stats.childKey]!;
      }
    }
    return OpeningTree._(games, nodes, rootKey);
  }

  /// Parties retenues par le filtre.
  final List<GameRecord> games;
  final Map<String, PositionNode> _nodes;
  final String rootKey;

  PositionNode get root => _nodes[rootKey]!;

  PositionNode? node(String key) => _nodes[key];

  /// Score global des parties retenues, entre 0 et 1.
  double get score =>
      games.isEmpty ? 0 : games.fold<double>(0, (sum, g) => sum + g.score) / games.length;

  /// Suit une ligne en SAN depuis la position initiale.
  PositionNode? follow(List<String> sans) {
    var node = root;
    for (final san in sans) {
      final stats = node.move(san);
      if (stats == null) return null;
      node = _nodes[stats.childKey]!;
    }
    return node;
  }
}
