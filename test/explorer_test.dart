import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linedrill/data/lichess_explorer.dart';

const _body = '''
{"white":100,"draws":50,"black":50,"moves":[
 {"uci":"d2d4","san":"d4","averageRating":2400,"white":60,"draws":30,"black":10},
 {"uci":"g1f3","san":"Nf3","averageRating":2380,"white":40,"draws":20,"black":40}
]}''';

void main() {
  final fen = Chess.initial.fen;

  test('maîtres : requête et parsing', () async {
    late Uri seen;
    late Map<String, String> headers;
    final client = LichessExplorerClient(httpClient: MockClient((r) async {
      seen = r.url;
      headers = r.headers;
      return http.Response(_body, 200);
    }));
    final result = await client.explore(fen, ExplorerDatabase.masters, token: 'lip_x');
    expect(seen.host, 'explorer.lichess.ovh');
    expect(seen.path, '/masters');
    expect(seen.queryParameters['fen'], fen);
    expect(headers['Authorization'], 'Bearer lip_x');
    expect(result.moves.map((m) => m.san), ['d4', 'Nf3']);
    expect(result.total, 200);
    expect(result.moves.first.scoreFor(Side.white), closeTo(0.75, 0.001));
    expect(result.moves.first.scoreFor(Side.black), closeTo(0.25, 0.001));
  });

  test('niveau club : bullet et blitz, tranches Elo', () async {
    late Uri seen;
    final client = LichessExplorerClient(httpClient: MockClient((r) async {
      seen = r.url;
      return http.Response(_body, 200);
    }));
    await client.explore(fen, ExplorerDatabase.club, token: 'lip_x');
    expect(seen.path, '/lichess');
    expect(seen.queryParameters['speeds'], 'bullet,blitz');
    expect(seen.queryParameters['ratings'], LichessExplorerClient.clubRatings);
  });

  test('sans jeton ou jeton refusé', () async {
    final client = LichessExplorerClient(httpClient: MockClient((_) async => http.Response('', 401)));
    expect(client.explore(fen, ExplorerDatabase.masters, token: null),
        throwsA(isA<ExplorerException>()));
    expect(client.explore(fen, ExplorerDatabase.masters, token: 'bad'),
        throwsA(isA<ExplorerException>().having((e) => e.message, 'message', contains('refusé'))));
  });
}
