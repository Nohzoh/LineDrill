import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/game_record.dart';
import '../core/opening_tree.dart';
import '../core/weak_lines.dart';
import '../data/chesscom_client.dart';
import '../data/game_store.dart';
import '../data/import_service.dart';

final importServiceProvider = FutureProvider<ImportService>((ref) async {
  final dir = await getApplicationSupportDirectory();
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
