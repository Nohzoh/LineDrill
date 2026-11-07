import 'dart:convert';

import 'package:http/http.dart' as http;

/// Mois d'archive Chess.com.
class ArchiveMonth implements Comparable<ArchiveMonth> {
  const ArchiveMonth(this.year, this.month);

  final int year;
  final int month;

  /// Identifiant stable, ex. `2026-10`.
  String get key => '$year-${month.toString().padLeft(2, '0')}';

  @override
  int compareTo(ArchiveMonth other) =>
      year != other.year ? year.compareTo(other.year) : month.compareTo(other.month);

  @override
  bool operator ==(Object other) =>
      other is ArchiveMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => key;
}

class ChessComException implements Exception {
  ChessComException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Client de l'API publique Chess.com (sans authentification).
class ChessComClient {
  ChessComClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const _base = 'https://api.chess.com/pub/player';
  static const _headers = {'User-Agent': 'LineDrill'};

  final http.Client _http;

  /// Mois disponibles pour [username], du plus ancien au plus récent.
  Future<List<ArchiveMonth>> archives(String username) async {
    final uri = Uri.parse('$_base/${username.toLowerCase()}/games/archives');
    final body = await _get(uri, username);
    final urls = (jsonDecode(body)['archives'] as List).cast<String>();
    final months = <ArchiveMonth>[];
    for (final url in urls) {
      final segments = Uri.parse(url).pathSegments;
      final year = int.tryParse(segments[segments.length - 2]);
      final month = int.tryParse(segments.last);
      if (year != null && month != null) months.add(ArchiveMonth(year, month));
    }
    months.sort();
    return months;
  }

  /// Toutes les parties de [username] pour [month], en PGN.
  Future<String> monthPgn(String username, ArchiveMonth month) {
    final mm = month.month.toString().padLeft(2, '0');
    final uri = Uri.parse('$_base/${username.toLowerCase()}/games/${month.year}/$mm/pgn');
    return _get(uri, username);
  }

  Future<String> _get(Uri uri, String username) async {
    final http.Response response;
    try {
      response = await _http.get(uri, headers: _headers);
    } catch (e) {
      throw ChessComException('Connexion à Chess.com impossible.');
    }
    if (response.statusCode == 404) {
      throw ChessComException('Joueur « $username » introuvable sur Chess.com.');
    }
    if (response.statusCode != 200) {
      throw ChessComException('Chess.com a répondu ${response.statusCode}.');
    }
    return utf8.decode(response.bodyBytes);
  }

  void close() => _http.close();
}
