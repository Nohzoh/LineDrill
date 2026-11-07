import 'dart:io';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/game_record.dart';
import '../core/opening_tree.dart';
import '../core/repertoire.dart';
import '../core/weak_lines.dart';
import '../data/chesscom_client.dart';
import '../data/game_store.dart';
import '../data/import_service.dart';
import '../data/lichess_explorer.dart';
import '../data/repertoire_store.dart';

/// Dossier privé de l'appli, où vivent parties, répertoire et réglages.
final appDirProvider = FutureProvider<Directory>((ref) => getApplicationSupportDirectory());

final importServiceProvider = FutureProvider<ImportService>((ref) async {
  final dir = await ref.watch(appDirProvider.future);
  final client = ChessComClient();
  ref.onDispose(client.close);
  return ImportService(client, GameStore(dir));
});

/// Parties importées et pseudo associé.
class GamesState {
  const GamesState({this.username, this.games = const []});

  final String? username;
  final List<GameRecord> games;
}

class GamesNotifier extends AsyncNotifier<GamesState> {
  @override
  Future<GamesState> build() async {
    final service = await ref.watch(importServiceProvider.future);
    return GamesState(
      username: await service.store.username(),
      games: await service.loadGames(),
    );
  }

  /// Importe les parties ; l'erreur éventuelle est relancée à l'appelant
  /// et l'état précédent est conservé.
  Future<void> sync(String username, {int monthsBack = 3, ImportProgress? onProgress}) async {
    final service = await ref.read(importServiceProvider.future);
    await service.sync(username, monthsBack: monthsBack, onProgress: onProgress);
    state = AsyncData(GamesState(
      username: await service.store.username(),
      games: await service.loadGames(),
    ));
  }
}

final gamesProvider = AsyncNotifierProvider<GamesNotifier, GamesState>(GamesNotifier.new);

class FilterNotifier extends Notifier<GameFilter> {
  @override
  GameFilter build() => const GameFilter(color: Side.white);

  void setColor(Side color) {
    if (color == state.color) return;
    state = state.copyWith(color: color);
    ref.read(lineProvider.notifier).set(const []);
  }

  void toggleTimeClass(TimeClass timeClass) {
    final classes = {...state.timeClasses};
    if (!classes.remove(timeClass)) classes.add(timeClass);
    state = state.copyWith(timeClasses: classes);
  }
}

final filterProvider = NotifierProvider<FilterNotifier, GameFilter>(FilterNotifier.new);

/// Arbre des parties filtrées ; `null` tant que les parties chargent.
final treeProvider = Provider<OpeningTree?>((ref) {
  final games = ref.watch(gamesProvider).value?.games;
  if (games == null) return null;
  return OpeningTree.build(games, ref.watch(filterProvider));
});

/// Ligne affichée dans l'arbre, en SAN depuis la position initiale.
class LineNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void set(List<String> line) => state = List.unmodifiable(line);
}

final lineProvider = NotifierProvider<LineNotifier, List<String>>(LineNotifier.new);

/// Lignes faibles de l'arbre filtré.
final weakLinesProvider = Provider<List<WeakLine>>((ref) {
  final tree = ref.watch(treeProvider);
  return tree == null ? const [] : weakLines(tree);
});

final repertoireStoreProvider = FutureProvider<RepertoireStore>(
  (ref) async => RepertoireStore(await ref.watch(appDirProvider.future)),
);

/// Répertoire de l'utilisateur, enregistré à chaque modification.
class RepertoireNotifier extends AsyncNotifier<Repertoire> {
  @override
  Future<Repertoire> build() async =>
      (await ref.watch(repertoireStoreProvider.future)).loadRepertoire();

  Future<void> _save(Repertoire Function(Repertoire) change) async {
    final next = change(await future);
    state = AsyncData(next);
    await (await ref.read(repertoireStoreProvider.future)).saveRepertoire(next);
  }

  Future<void> setReference(Side color, Position position, String san, List<String> line) =>
      _save((r) => r.withEntry(RepertoireEntry(
            color: color,
            positionKey: positionKey(position),
            san: san,
            line: List.unmodifiable(line),
          )));

  Future<void> remove(Side color, String key) => _save((r) => r.without(color, key));
}

final repertoireProvider =
    AsyncNotifierProvider<RepertoireNotifier, Repertoire>(RepertoireNotifier.new);

/// Respect du répertoire dans les parties filtrées (couleur et cadence).
final repertoireUsageProvider = Provider<Map<String, EntryUsage>>((ref) {
  final tree = ref.watch(treeProvider);
  final repertoire = ref.watch(repertoireProvider).value;
  if (tree == null || repertoire == null) return const {};
  return repertoireUsage(tree.games, repertoire);
});

/// Jeton personnel Lichess pour l'explorateur.
class LichessTokenNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => (await ref.watch(repertoireStoreProvider.future)).lichessToken();

  Future<void> set(String? token) async {
    await (await ref.read(repertoireStoreProvider.future)).setLichessToken(token);
    state = AsyncData(await (await ref.read(repertoireStoreProvider.future)).lichessToken());
  }
}

final lichessTokenProvider =
    AsyncNotifierProvider<LichessTokenNotifier, String?>(LichessTokenNotifier.new);

final explorerClientProvider = Provider<LichessExplorerClient>((ref) {
  final client = LichessExplorerClient();
  ref.onDispose(client.close);
  return client;
});
