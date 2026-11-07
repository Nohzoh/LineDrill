import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linedrill/data/chesscom_client.dart';
import 'package:linedrill/data/game_store.dart';
import 'package:linedrill/data/import_service.dart';

String _game(String month) => '[White "Lappeau"]\n[Black "x"]\n[Result "1-0"]\n'
    '[TimeControl "60"]\n[UTCDate "2026.$month.01"]\n\n1. e4 e5 1-0\n';

void main() {
  late Directory tmp;
  late List<String> requested;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('linedrill');
    requested = [];
  });

  tearDown(() => tmp.delete(recursive: true));

  ImportService service() {
    final mock = MockClient((request) async {
      requested.add(request.url.path);
      expect(request.headers['User-Agent'], 'LineDrill');
      if (request.url.path.endsWith('/archives')) {
        return http.Response(
          '{"archives":["https://api.chess.com/pub/player/lappeau/games/2026/08",'
          '"https://api.chess.com/pub/player/lappeau/games/2026/09",'
          '"https://api.chess.com/pub/player/lappeau/games/2026/10"]}',
          200,
        );
      }
      final month = request.url.pathSegments[request.url.pathSegments.length - 2];
      return http.Response(_game(month), 200);
    });
    return ImportService(ChessComClient(httpClient: mock), GameStore(tmp));
  }

  test('importe les derniers mois puis les relit', () async {
    final s = service();
    await s.sync('Lappeau', monthsBack: 2);
    expect(requested, [
      '/pub/player/lappeau/games/archives',
      '/pub/player/lappeau/games/2026/09/pgn',
      '/pub/player/lappeau/games/2026/10/pgn',
    ]);
    final games = await s.loadGames();
    expect(games, hasLength(2));
    expect(games.map((g) => g.date), ['2026.09.01', '2026.10.01']);
  });

  test('ne retélécharge que le mois le plus récent', () async {
    final s = service();
    await s.sync('Lappeau', monthsBack: 2);
    requested.clear();
    await s.sync('Lappeau', monthsBack: 2);
    expect(requested, [
      '/pub/player/lappeau/games/archives',
      '/pub/player/lappeau/games/2026/10/pgn',
    ]);
  });

  test('un changement de pseudo efface les parties', () async {
    final store = GameStore(tmp);
    await store.setUsername('Lappeau');
    await store.writeMonth(const ArchiveMonth(2026, 10), _game('10'));
    await store.setUsername('Autre');
    expect(await store.storedMonths(), isEmpty);
  });

  test('joueur inconnu', () async {
    final client = ChessComClient(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    expect(client.archives('personne'), throwsA(isA<ChessComException>()));
  });
}
