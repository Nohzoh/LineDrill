import '../core/game_record.dart';
import '../core/pgn_import.dart';
import 'chesscom_client.dart';
import 'game_store.dart';

/// Progression d'un import : [done] mois traités sur [total].
typedef ImportProgress = void Function(int done, int total);

/// Synchronise les parties Chess.com avec le stockage local.
class ImportService {
  ImportService(this.client, this.store);

  final ChessComClient client;
  final GameStore store;

  /// Importe les [monthsBack] derniers mois de [username].
  ///
  /// Les mois déjà stockés ne sont pas retéléchargés, sauf le plus récent
  /// (le mois en cours se remplit encore).
  Future<void> sync(String username, {int monthsBack = 3, ImportProgress? onProgress}) async {
    await store.setUsername(username);
    final available = await client.archives(username);
    final wanted = available.length > monthsBack
        ? available.sublist(available.length - monthsBack)
        : available;
    final stored = (await store.storedMonths()).toSet();
    final toFetch = [
      for (final m in wanted)
        if (!stored.contains(m) || m == wanted.last) m,
    ];
    for (var i = 0; i < toFetch.length; i++) {
      onProgress?.call(i, toFetch.length);
      final pgn = await client.monthPgn(username, toFetch[i]);
      await store.writeMonth(toFetch[i], pgn);
    }
    onProgress?.call(toFetch.length, toFetch.length);
  }

  /// Toutes les parties stockées, parsées.
  Future<List<GameRecord>> loadGames() async {
    final username = await store.username();
    if (username == null) return [];
    final games = <GameRecord>[];
    for (final month in await store.storedMonths()) {
      games.addAll(parseGames(await store.readMonth(month), username));
    }
    return games;
  }
}
