import 'dart:convert';

import 'package:dartchess/dartchess.dart';
import 'package:http/http.dart' as http;

/// Base de parties interrogée.
enum ExplorerDatabase {
  /// Parties de maîtres (OTB, 2200+).
  masters('Maîtres'),

  /// Parties Lichess en bullet et blitz, joueurs de niveau club.
  club('Niveau club');

  const ExplorerDatabase(this.label);

  final String label;
}

/// Un coup de l'explorateur et ses résultats.
class ExplorerMove {
  const ExplorerMove({
    required this.san,
    required this.uci,
    required this.white,
    required this.draws,
    required this.black,
    this.averageRating,
  });

  factory ExplorerMove.fromJson(Map<String, Object?> json) => ExplorerMove(
        san: json['san']! as String,
        uci: json['uci']! as String,
        white: (json['white'] as num?)?.toInt() ?? 0,
        draws: (json['draws'] as num?)?.toInt() ?? 0,
        black: (json['black'] as num?)?.toInt() ?? 0,
        averageRating: (json['averageRating'] as num?)?.toInt(),
      );

  final String san;
  final String uci;
  final int white;
  final int draws;
  final int black;
  final int? averageRating;

  int get total => white + draws + black;

  /// Score du point de vue de [side], entre 0 et 1.
  double scoreFor(Side side) {
    if (total == 0) return 0;
    final wins = side == Side.white ? white : black;
    return (wins + draws / 2) / total;
  }
}

class ExplorerResult {
  const ExplorerResult(this.moves);

  final List<ExplorerMove> moves;

  int get total => moves.fold(0, (sum, m) => sum + m.total);
}

class ExplorerException implements Exception {
  ExplorerException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Client de l'explorateur d'ouvertures Lichess, qui demande un jeton
/// personnel (créé sur lichess.org, sans aucune permission cochée).
class LichessExplorerClient {
  LichessExplorerClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const _host = 'explorer.lichess.ovh';

  /// Tranches Elo Lichess utilisées pour la base « niveau club ».
  static const clubRatings = '1000,1200,1400,1600';

  final http.Client _http;

  Future<ExplorerResult> explore(
    String fen,
    ExplorerDatabase database, {
    required String? token,
  }) async {
    if (token == null || token.isEmpty) {
      throw ExplorerException('Ajoute ton jeton Lichess dans les réglages pour utiliser l\'explorateur.');
    }
    final uri = switch (database) {
      ExplorerDatabase.masters => Uri.https(_host, '/masters', {
          'fen': fen,
          'moves': '12',
          'topGames': '0',
        }),
      ExplorerDatabase.club => Uri.https(_host, '/lichess', {
          'variant': 'standard',
          'fen': fen,
          'speeds': 'bullet,blitz',
          'ratings': clubRatings,
          'moves': '12',
          'topGames': '0',
          'recentGames': '0',
        }),
    };
    final http.Response response;
    try {
      response = await _http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'User-Agent': 'LineDrill',
      });
    } catch (_) {
      throw ExplorerException('Connexion à l\'explorateur Lichess impossible.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ExplorerException('Jeton Lichess refusé : vérifie-le dans les réglages.');
    }
    if (response.statusCode == 429) {
      throw ExplorerException('Trop de requêtes vers Lichess, réessaie dans une minute.');
    }
    if (response.statusCode != 200) {
      throw ExplorerException('L\'explorateur Lichess a répondu ${response.statusCode}.');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
    final moves = (json['moves'] as List? ?? const [])
        .map((m) => ExplorerMove.fromJson((m as Map).cast<String, Object?>()))
        .toList();
    return ExplorerResult(moves);
  }

  void close() => _http.close();
}
