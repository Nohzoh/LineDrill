import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import '../engine/chess_engine.dart';
import 'explain.dart';
import 'opening_tree.dart';

/// Chances de gain entre −1 et 1 pour une évaluation en centipions
/// (même courbe que Lichess).
double winChances(int cp) {
  final clamped = cp.clamp(-1000, 1000);
  return 2 / (1 + math.exp(-0.00368208 * clamped)) - 1;
}

/// Qualité d'un coup de l'utilisateur.
enum MoveQuality {
  /// Coup de référence du répertoire.
  book('Coup du répertoire'),

  /// Autre coup que celui de mon répertoire.
  offBook('Hors répertoire'),
  good('Bon coup'),
  inaccuracy('Imprécision'),
  mistake('Erreur'),
  blunder('Gaffe');

  const MoveQuality(this.label);

  final String label;

  /// Un coup de cette qualité met la partie en pause pour correction.
  bool get needsCorrection => this == offBook || this == mistake || this == blunder;

  /// Seuils Lichess sur la perte de chances de gain.
  static MoveQuality fromLoss(double loss) {
    if (loss >= 0.3) return blunder;
    if (loss >= 0.2) return mistake;
    if (loss >= 0.1) return inaccuracy;
    return good;
  }
}

/// Force de l'adversaire en phase moteur.
enum OpponentLevel {
  easy('Facile', depth: 8, maxLoss: 0.45, temperature: 0.18),
  medium('Moyen', depth: 10, maxLoss: 0.25, temperature: 0.08),
  hard('Difficile', depth: 14, maxLoss: 0.06, temperature: 0.02);

  const OpponentLevel(this.label, {required this.depth, required this.maxLoss, required this.temperature});

  final String label;

  /// Profondeur d'analyse de Stockfish.
  final int depth;

  /// Perte maximale de chances de gain qu'un coup adverse peut concéder.
  final double maxLoss;

  /// Plus elle est haute, plus les coups moins bons sont choisis souvent.
  final double temperature;

  /// Nombre de lignes demandées au moteur pour choisir un coup.
  int get multiPv => this == hard ? 2 : 5;
}

/// Choisit un coup adverse parmi les lignes du moteur, au hasard pondéré :
/// les coups proches du meilleur sont plus probables, ceux qui perdent plus
/// que [OpponentLevel.maxLoss] sont exclus.
EngineLine pickEngineMove(List<EngineLine> lines, OpponentLevel level, math.Random random) {
  final best = winChances(lines.first.cp);
  final candidates = [
    for (final l in lines)
      if (best - winChances(l.cp) <= level.maxLoss) l,
  ];
  final weights = [
    for (final l in candidates) math.exp(-(best - winChances(l.cp)) / level.temperature),
  ];
  return candidates[_weightedIndex(weights, random)];
}

/// Choisit une réponse adverse parmi celles de mes vraies parties, en
/// proportion de leur fréquence ; `null` si la position n'y apparaît pas.
MoveStats? pickBookMove(PositionNode? node, math.Random random) {
  final moves = node?.moves ?? const [];
  if (moves.isEmpty) return null;
  return moves[_weightedIndex([for (final m in moves) m.count.toDouble()], random)];
}

int _weightedIndex(List<double> weights, math.Random random) {
  final total = weights.fold<double>(0, (s, w) => s + w);
  var r = random.nextDouble() * total;
  for (var i = 0; i < weights.length; i++) {
    r -= weights[i];
    if (r < 0) return i;
  }
  return weights.length - 1;
}

/// Verdict sur un coup de l'utilisateur.
class MoveVerdict {
  const MoveVerdict(this.quality, {this.better, this.loss = 0, this.explanation});

  MoveVerdict withExplanation(MoveExplanation? explanation) =>
      MoveVerdict(quality, better: better, loss: loss, explanation: explanation);

  final MoveQuality quality;

  /// Coup conseillé à la place, en SAN : le coup de référence en phase
  /// répertoire, le meilleur coup du moteur sinon.
  final String? better;

  /// Perte de chances de gain (0 à 2).
  final double loss;

  /// Pourquoi le coup est moins bon (imprécision, erreur, gaffe).
  final MoveExplanation? explanation;
}

/// Juge un coup à partir des lignes du moteur avant le coup.
///
/// [playedCp] est l'évaluation après le coup joué, du point de vue du
/// joueur qui l'a joué ; [bestLine] la meilleure ligne avant le coup.
MoveVerdict judgeEngineMove({
  required EngineLine bestLine,
  required int playedCp,
  required String playedUci,
  required String bestSan,
}) {
  if (playedUci == bestLine.uci) return const MoveVerdict(MoveQuality.good);
  final loss = math.max(0.0, winChances(bestLine.cp) - winChances(playedCp));
  return MoveVerdict(MoveQuality.fromLoss(loss), better: bestSan, loss: loss);
}

/// Coup moteur (UCI standard, roque en `e1g1`) converti pour [position].
Move engineMove(Position position, String uci) {
  final move = Move.parse(uci)!;
  return move is NormalMove ? position.normalizeMove(move) : move;
}

/// Juge mon coup [move] joué depuis [before] avec le moteur.
///
/// Les coups sont comparés en SAN, pour que le roque soit reconnu quelle
/// que soit sa notation (roi vers g1 ou roi vers la tour).
Future<MoveVerdict> judgeMove(ChessEngine engine, Position before, Move move, {int depth = 12}) async {
  final lines = await engine.analyse(before.fen, depth: depth, multiPv: 3);
  if (lines.isEmpty) return const MoveVerdict(MoveQuality.good);
  String sanOf(String uci) => before.makeSan(engineMove(before, uci)).$2;
  final best = lines.first;
  final bestSan = sanOf(best.uci);
  final normalized = move is NormalMove ? before.normalizeMove(move) : move;
  final (after, playedSan) = before.makeSan(normalized);
  if (playedSan == bestSan) return const MoveVerdict(MoveQuality.good);
  final int playedCp;

  /// Suite du moteur après mon coup (adversaire au trait).
  var refutation = const <String>[];
  final known = lines.where((l) => sanOf(l.uci) == playedSan).firstOrNull;
  if (known != null) {
    playedCp = known.cp;
    refutation = known.pv.skip(1).toList();
  } else if (after.isCheckmate) {
    playedCp = mateScore(1);
  } else if (after.isGameOver) {
    playedCp = 0;
  } else {
    final reply = await engine.analyse(after.fen, depth: depth);
    playedCp = reply.isEmpty ? 0 : -reply.first.cp;
    if (reply.isNotEmpty) refutation = reply.first.pv;
  }
  final verdict = judgeEngineMove(bestLine: best, playedCp: playedCp, playedUci: normalized.uci, bestSan: bestSan);
  if (verdict.quality == MoveQuality.good) return verdict;

  // La ligne MultiPV du coup joué est souvent courte : on redemande une
  // suite complète pour pouvoir l'expliquer.
  if (refutation.length < 4 && !after.isGameOver) {
    final reply = await engine.analyse(after.fen, depth: depth);
    if (reply.isNotEmpty) refutation = reply.first.pv;
  }
  return verdict.withExplanation(explainMove(
    before: before,
    move: normalized,
    best: best,
    refutation: refutation,
    playedCp: playedCp,
  ));
}
