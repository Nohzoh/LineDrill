import 'package:multistockfish/multistockfish.dart';

import 'chess_engine.dart';

/// Lance Stockfish 19 (réseau NNUE léger embarqué, sans téléchargement).
///
/// Stockfish est sous licence GPLv3 : distribuer l'APK implique de
/// distribuer aussi le code de l'appli sous GPL.
Future<ChessEngine> startStockfish() async {
  final stockfish = await Stockfish.create(flavor: StockfishFlavor.light);
  final engine = UciEngine(
    output: stockfish.stdout,
    send: (line) => stockfish.stdin = line,
    onDispose: stockfish.dispose,
  );
  stockfish.stdin = 'setoption name Threads value 2';
  stockfish.stdin = 'setoption name Hash value 32';
  stockfish.stdin = 'ucinewgame';
  return engine;
}
