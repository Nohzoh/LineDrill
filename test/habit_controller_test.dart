import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/app/habit_controller.dart';
import 'package:linedrill/app/play_controller.dart';
import 'package:linedrill/app/providers.dart';
import 'package:linedrill/core/game_record.dart';
import 'package:linedrill/core/opening_report.dart';
import 'package:linedrill/core/opening_tree.dart';
import 'package:linedrill/core/openings.dart';
import 'package:linedrill/core/repertoire.dart';
import 'package:linedrill/core/training.dart';
import 'package:linedrill/engine/chess_engine.dart';

String _key(String moves) {
  Position p = Chess.initial;
  for (final san in moves.isEmpty ? <String>[] : moves.split(' ')) {
    p = p.play(p.parseSan(san)!);
  }
  return positionKey(p);
}

List<GameRecord> _repeat(int n, String moves, double score) => List.generate(
      n,
      (_) => GameRecord(color: Side.white, score: score, timeClass: TimeClass.bullet, sans: moves.split(' ')),
    );

class _Games extends GamesNotifier {
  @override
  Future<GamesState> build() async => GamesState(username: 'me', games: [
        ..._repeat(11, 'e4 c5 Nf3', 0),
        ..._repeat(9, 'e4 c5 d4', 1),
        ..._repeat(10, 'e4 e5 Nf3', 1),
      ]);
}

/// Moteur factice : tout se vaut, sauf 2. Nf3 contre la Sicilienne, qui perd
/// gros là où 2. d4 est le meilleur coup.
class _PickyEngine implements ChessEngine {
  final asked = <String>[];
  Object? failure;

  /// Position où [failure] est levée ; `null` : à la première analyse.
  String? failAt;

  /// Le moteur répond, mais sans aucune ligne.
  bool silent = false;

  @override
  Future<List<EngineLine>> analyse(String fen, {int depth = 12, int multiPv = 1}) async {
    final p = Chess.fromSetup(Setup.parseFen(fen));
    final key = positionKey(p);
    if (failure != null && (failAt == null || failAt == key)) throw failure!;
    asked.add(key);
    if (silent) return const [];
    if (key == _key('e4 c5')) return [const EngineLine('d2d4', 40)];
    if (key == _key('e4 c5 Nf3')) return [const EngineLine('d7d6', 400)];
    final first = p.legalMoves.entries.firstWhere((e) => e.value.isNotEmpty);
    final uci = NormalMove(from: first.key, to: first.value.squares.first).uci;
    return [EngineLine(uci, p.turn == Side.white ? 20 : -20)];
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory tmp;
  late _PickyEngine engine;

  ProviderContainer newContainer() {
    final container = ProviderContainer(overrides: [
      appDirProvider.overrideWith((ref) async => tmp),
      gamesProvider.overrideWith(_Games.new),
      engineProvider.overrideWith((ref) async => engine),
      openingBookProvider.overrideWith((ref) async => OpeningBook.empty),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<OpeningReport> report(ProviderContainer container) async {
    await container.read(gamesProvider.future);
    await container.read(repertoireProvider.future);
    await container.read(habitChecksProvider.future);
    await container.read(openingBookProvider.future);
    // Lu à part : écrit `read(…)!` dans le `return`, le type attendu perd son
    // `?` et Riverpod ne retrouve plus le provider.
    final report = container.read(openingReportProvider);
    return report!;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('linedrill');
    engine = _PickyEngine();
  });

  tearDown(() => tmp.delete(recursive: true));

  test('juge mes coups, corrige le mauvais et repasse sur le coup de rechange', () async {
    final container = newContainer();
    expect((await report(container)).unchecked.map((h) => h.move.san), ['e4']);

    await container.read(habitCheckProvider.notifier).start();
    final state = container.read(habitCheckProvider);
    expect(state.running, isFalse);
    expect(state.error, isNull);
    expect(state.color, Side.white);
    // 1. e4, puis 2. Nf3 dans chaque variante, puis 2. d4 proposé à la place
    // de 2. Nf3 contre la Sicilienne.
    expect(state.done, 4);
    // Sans explication à produire : une analyse par coup, deux quand le coup
    // n'est pas le premier choix du moteur.
    expect(engine.asked, hasLength(7));

    final checked = await report(container);
    expect(checked.unchecked, isEmpty);
    final sicilian = checked.steps.singleWhere((s) => s.line.join(' ') == 'e4 c5');
    expect(sicilian.status, HabitStatus.toFix);
    expect(sicilian.check!.quality, MoveQuality.blunder);
    expect(sicilian.reference, 'd4');
    expect(checked.steps.where((s) => s.status == HabitStatus.toFix), hasLength(1));

    final repertoire = container.read(repertoireProvider).value!;
    final entries = habitEntries(checked, Side.white, repertoire);
    expect({for (final e in entries) e.line.join(' '): e.san}, {'': 'e4', 'e4 c5': 'd4', 'e4 e5': 'Nf3'});
    await container.read(repertoireProvider.notifier).addMissing(entries);
    expect(habitEntries(await report(container), Side.white, container.read(repertoireProvider).value!), isEmpty);
  });

  test('avis gardés : rien à rejuger au lancement suivant', () async {
    final first = newContainer();
    await report(first);
    await first.read(habitCheckProvider.notifier).start();
    expect(engine.asked, isNotEmpty);
    engine.asked.clear();

    final container = newContainer();
    expect((await report(container)).unchecked, isEmpty);
    await container.read(habitCheckProvider.notifier).start();
    expect(engine.asked, isEmpty);
    expect(container.read(habitCheckProvider).done, 0);
  });

  test('un coup de référence existant n\'est pas remplacé', () async {
    final container = newContainer();
    await report(container);
    final e4c5 = Chess.initial.play(Move.parse('e2e4')!).play(Move.parse('c7c5')!);
    await container.read(repertoireProvider.notifier).setReference(Side.white, e4c5, 'Nf3', const ['e4', 'c5']);
    await container.read(habitCheckProvider.notifier).start();

    final checked = await report(container);
    final entries = habitEntries(checked, Side.white, container.read(repertoireProvider).value!);
    await container.read(repertoireProvider.notifier).addMissing(entries);
    // Même proposé à nouveau, un coup de référence existant reste, et reste à sa place.
    await container.read(repertoireProvider.notifier).addMissing([
      RepertoireEntry(color: Side.white, positionKey: _key('e4 c5'), san: 'd4', line: const ['e4', 'c5']),
    ]);
    final repertoire = container.read(repertoireProvider).value!;
    expect(repertoire.lookup(Side.white, _key('e4 c5'))!.san, 'Nf3');
    expect(repertoire.entries, hasLength(3));
    expect(repertoire.entries.first.positionKey, _key('e4 c5'));
  });

  test('moteur en panne : erreur affichable, rien d\'enregistré', () async {
    engine.failure = StateError('pas de moteur');
    final container = newContainer();
    await report(container);
    await container.read(habitCheckProvider.notifier).start();
    final state = container.read(habitCheckProvider);
    expect(state.running, isFalse);
    expect(state.error, contains('pas de moteur'));
    expect((await report(container)).unchecked, isNotEmpty);
  });

  test('panne en cours de route : les coups déjà jugés sont gardés', () async {
    engine
      ..failure = StateError('moteur perdu')
      ..failAt = _key('e4 e5');
    final container = newContainer();
    await report(container);
    await container.read(habitCheckProvider.notifier).start();
    expect(container.read(habitCheckProvider).error, contains('moteur perdu'));

    final saved = await newContainer().read(habitChecksProvider.future);
    expect(saved.keys, containsAll([habitCheckKey(_key(''), 'e4'), habitCheckKey(_key('e4 c5'), 'Nf3')]));
    expect(saved.containsKey(habitCheckKey(_key('e4 e5'), 'Nf3')), isFalse);
  });

  test('moteur muet : pas d\'avis par défaut, rien d\'enregistré', () async {
    engine.silent = true;
    final container = newContainer();
    await report(container);
    await container.read(habitCheckProvider.notifier).start();
    expect(container.read(habitCheckProvider).error, contains('rien répondu'));
    expect(await newContainer().read(habitChecksProvider.future), isEmpty);
  });

  test('le moteur est relancé après un démarrage raté', () async {
    var starts = 0;
    final container = ProviderContainer(overrides: [
      appDirProvider.overrideWith((ref) async => tmp),
      gamesProvider.overrideWith(_Games.new),
      engineProvider.overrideWith((ref) async => ++starts == 1 ? throw StateError('pas démarré') : engine),
      openingBookProvider.overrideWith((ref) async => OpeningBook.empty),
    ]);
    addTearDown(container.dispose);
    await report(container);
    await container.read(habitCheckProvider.notifier).start();
    expect(container.read(habitCheckProvider).error, contains('pas démarré'));

    await container.read(habitCheckProvider.notifier).start();
    expect(container.read(habitCheckProvider).error, isNull);
    expect(container.read(habitCheckProvider).done, 4);
  });

  test('la couleur du lancement est gardée si l\'écran en change', () async {
    final container = newContainer();
    await report(container);
    final run = container.read(habitCheckProvider.notifier).start();
    container.read(filterProvider.notifier).setColor(Side.black);
    await run;
    expect(container.read(habitCheckProvider).color, Side.white);
    expect(container.read(habitCheckProvider).done, 4);
  });
}
