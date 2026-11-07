import 'package:dartchess/dartchess.dart';

import 'game_record.dart';

/// Nombre de demi-coups conservés par partie pour l'arbre.
const int maxPlies = 16;

/// Transforme un PGN multi-parties (export Chess.com) en [GameRecord].
///
/// Les parties où [username] ne joue pas, les variantes non standard et
/// les parties sans résultat sont ignorées.
List<GameRecord> parseGames(String pgn, String username) {
  final me = username.toLowerCase();
  final records = <GameRecord>[];
  for (final game in PgnGame.parseMultiGamePgn(pgn)) {
    final record = gameToRecord(game, me);
    if (record != null) records.add(record);
  }
  return records;
}

/// Convertit une partie, ou renvoie `null` si elle doit être ignorée.
GameRecord? gameToRecord(PgnGame<PgnNodeData> game, String usernameLower) {
  final h = game.headers;
  final variant = h['Variant'];
  if (variant != null && variant.toLowerCase() != 'standard') return null;
  if (h['SetUp'] == '1' || h.containsKey('FEN')) return null;

  final Side color;
  if (h['White']?.toLowerCase() == usernameLower) {
    color = Side.white;
  } else if (h['Black']?.toLowerCase() == usernameLower) {
    color = Side.black;
  } else {
    return null;
  }

  final whiteScore = switch (h['Result']) {
    '1-0' => 1.0,
    '0-1' => 0.0,
    '1/2-1/2' => 0.5,
    _ => null,
  };
  if (whiteScore == null) return null;

  final sans = <String>[];
  Position position = Chess.initial;
  for (final node in game.moves.mainline()) {
    if (sans.length >= maxPlies) break;
    final move = position.parseSan(node.san);
    if (move == null) break;
    final (next, san) = position.makeSan(move);
    sans.add(san);
    position = next;
  }

  return GameRecord(
    color: color,
    score: color == Side.white ? whiteScore : 1 - whiteScore,
    timeClass: TimeClass.fromTimeControl(h['TimeControl']),
    sans: List.unmodifiable(sans),
    link: h['Link'],
    date: h['UTCDate'] ?? h['Date'],
    elo: int.tryParse(h[color == Side.white ? 'WhiteElo' : 'BlackElo'] ?? ''),
  );
}
