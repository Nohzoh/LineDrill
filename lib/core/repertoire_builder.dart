import 'package:dartchess/dartchess.dart';

import '../engine/chess_engine.dart';
import 'opening_tree.dart';
import 'repertoire.dart';
import 'training.dart';

/// Ce que le générateur propose pour une position où c'est à moi de jouer.
enum ProposalStatus {
  /// Mon coup habituel est bon : on le garde.
  kept('Coup habituel'),

  /// Mon coup habituel est une imprécision, ou une erreur qui garde un net
  /// avantage : gardé, mais il y avait mieux.
  review('À vérifier'),

  /// Mon coup habituel est une erreur ou une gaffe : remplacé.
  corrected('Corrigé');

  const ProposalStatus(this.label);

  final String label;
}

/// Une proposition de coup de référence.
class Proposal {
  const Proposal({
    required this.position,
    required this.line,
    required this.usualSan,
    required this.usualCount,
    required this.reached,
    required this.san,
    required this.status,
    required this.verdict,
    this.existing,
  });

  /// Position où c'est à moi de jouer.
  final Position position;

  /// Coups qui y mènent, en SAN depuis la position initiale.
  final List<String> line;

  /// Coup que je joue le plus souvent ici, et dans combien de parties.
  final String usualSan;
  final int usualCount;

  /// Nombre de mes parties qui atteignent cette position.
  final int reached;

  /// Coup proposé comme référence.
  final String san;

  /// Meilleur coup selon Stockfish, s'il diffère de mon coup habituel.
  String? get better => verdict.better;

  final ProposalStatus status;

  /// Jugement de Stockfish sur mon coup habituel (avec l'explication).
  final MoveVerdict verdict;

  /// Coup de référence déjà enregistré pour cette position, s'il existe.
  final String? existing;

  String get key => positionKey(position);

  /// Remplacerait un coup de référence différent déjà enregistré.
  bool get conflicts => existing != null && existing != san;
}

/// Réglages du parcours.
class BuilderOptions {
  const BuilderOptions({this.minGames = 3, this.maxPly = 14, this.depth = 12, this.keepAbove = 200});

  /// Un coup moins bon que le meilleur mais qui me laisse au moins cet
  /// avantage (centipions) n'est pas remplacé : il passe « à vérifier ».
  final int keepAbove;

  /// Une position doit être atteinte dans au moins ce nombre de parties.
  final int minGames;

  /// Profondeur maximale, en demi-coups depuis la position initiale.
  final int maxPly;

  /// Profondeur d'analyse de Stockfish.
  final int depth;
}

/// Prépare un répertoire pour [color] à partir de mes parties ([tree]) :
/// dans chaque position fréquente où c'est à moi de jouer, mon coup le plus
/// joué est jugé par [engine] ; s'il est bon il est gardé, sinon il est
/// remplacé par le meilleur coup. Toutes les réponses adverses fréquentes
/// sont suivies.
///
/// Une ligne corrigée par un coup que je n'ai jamais joué s'arrête là : mes
/// parties ne disent rien de la suite.
Future<List<Proposal>> buildRepertoire({
  required OpeningTree tree,
  required ChessEngine engine,
  required Side color,
  Repertoire? existing,
  BuilderOptions options = const BuilderOptions(),
  void Function(int analysed)? onProgress,
  bool Function()? cancelled,
}) async {
  final proposals = <Proposal>[];
  final visited = <String>{};
  var analysed = 0;

  // Parcours en largeur : les positions proches du début d'abord, celles
  // qui comptent le plus.
  var frontier = [(tree.root, const <String>[])];
  while (frontier.isNotEmpty) {
    final next = <(PositionNode, List<String>)>[];
    for (final (node, line) in frontier) {
      if (cancelled?.call() ?? false) return proposals;
      if (line.length >= options.maxPly || !visited.add(node.key)) continue;
      final moves = node.moves;
      final reached = moves.fold<int>(0, (s, m) => s + m.count);
      if (reached < options.minGames) continue;

      if (node.position.turn != color) {
        for (final reply in moves) {
          if (reply.count >= options.minGames) {
            next.add((tree.node(reply.childKey)!, [...line, reply.san]));
          }
        }
        continue;
      }

      final usual = moves.first;
      final verdict = await judgeMove(engine, node.position, usual.move, depth: options.depth);
      analysed++;
      onProgress?.call(analysed);

      final ProposalStatus status;
      final String san;
      final stillWinning = (verdict.playedCp ?? -100000) >= options.keepAbove;
      if (verdict.quality.needsCorrection && verdict.better != null && !stillWinning) {
        status = ProposalStatus.corrected;
        san = verdict.better!;
      } else {
        status = verdict.quality == MoveQuality.good || verdict.quality == MoveQuality.book
            ? ProposalStatus.kept
            : ProposalStatus.review;
        san = usual.san;
      }
      proposals.add(Proposal(
        position: node.position,
        line: line,
        usualSan: usual.san,
        usualCount: usual.count,
        reached: reached,
        san: san,
        status: status,
        verdict: verdict,
        existing: existing?.lookup(color, node.key)?.san,
      ));

      final chosen = node.move(san);
      if (chosen != null) next.add((tree.node(chosen.childKey)!, [...line, san]));
    }
    frontier = next;
  }
  return proposals;
}
