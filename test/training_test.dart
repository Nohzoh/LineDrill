import 'dart:io';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/app/play_controller.dart';
import 'package:linedrill/app/providers.dart';
import 'package:linedrill/core/game_record.dart';
import 'package:linedrill/core/opening_tree.dart';
import 'package:linedrill/core/training.dart';
import 'package:linedrill/engine/chess_engine.dart';

/// Moteur factice : une fonction décide des lignes pour chaque position.
class FakeEngine implements ChessEngine {
  FakeEngine(this.respond);

  final List<EngineLine> Function(Position position, int multiPv) respond;
  final List<String> analysed = [];

  @override
  Future<List<EngineLine>> analyse(String fen, {int depth = 12, int multiPv = 1}) async {
    analysed.add(fen);
    return respond(Chess.fromSetup(Setup.parseFen(fen)), multiPv);
  }

  @override
  Future<void> dispose() async {}
}

/// Par défaut : premier coup légal à 0, les autres à −20.
List<EngineLine> _flat(Position p, int multiPv) {
  final moves = [
    for (final entry in p.legalMoves.entries)
      for (final to in entry.value.squares) NormalMove(from: entry.key, to: to).uci,
  ]..sort();
  return [for (final (i, m) in moves.take(multiPv).indexed) EngineLine(m, i == 0 ? 0 : -20)];
}

GameRecord _g(String moves) =>
    GameRecord(color: Side.white, score: 1, timeClass: TimeClass.bullet, sans: moves.split(' '));

class _Games extends GamesNotifier {
  @override
  Future<GamesState> build() async => GamesState(username: 'me', games: [_g('e4 e5 Nf3 Nc6')]);
}

void main() {
  group('training', () {
    test('chances de gain et seuils', () {
      expect(winChances(0), 0);
      expect(winChances(1000), greaterThan(0.95));
      expect(winChances(-300), closeTo(-winChances(300), 1e-9));
      expect(MoveQuality.fromLoss(0.05), MoveQuality.good);
      expect(MoveQuality.fromLoss(0.15), MoveQuality.inaccuracy);
      expect(MoveQuality.fromLoss(0.25), MoveQuality.mistake);
      expect(MoveQuality.fromLoss(0.5), MoveQuality.blunder);
    });

    test('le moteur adverse exclut les coups trop mauvais', () {
      final lines = [const EngineLine('a', 50), const EngineLine('b', 40), const EngineLine('c', -600)];
      final random = math.Random(3);
      final picked = {
        for (var i = 0; i < 200; i++) pickEngineMove(lines, OpponentLevel.easy, random).uci,
      };
      expect(picked, containsAll(['a', 'b']));
      expect(picked, isNot(contains('c')));
      final hard = {
        for (var i = 0; i < 50; i++) pickEngineMove(lines, OpponentLevel.hard, random).uci,
      };
      expect(hard, isNot(contains('c')));
    });

    test('réponse du livre en proportion des parties', () {
      final games = [for (var i = 0; i < 9; i++) _g('e4 e5'), _g('e4 c5')];
      final tree = OpeningTree.build(games, const GameFilter(color: Side.white));
      final node = tree.follow(['e4']);
      final random = math.Random(1);
      final counts = <String, int>{};
      for (var i = 0; i < 500; i++) {
        final san = pickBookMove(node, random)!.san;
        counts[san] = (counts[san] ?? 0) + 1;
      }
      expect(counts['e5']! > counts['c5']! * 4, isTrue);
      expect(pickBookMove(tree.follow(['e4', 'e5']), random), isNull);
    });

    test('verdict moteur', () {
      const best = EngineLine('e2e4', 40);
      expect(judgeEngineMove(bestLine: best, playedCp: 40, playedUci: 'e2e4', bestSan: 'e4').quality,
          MoveQuality.good);
      final v = judgeEngineMove(bestLine: best, playedCp: -500, playedUci: 'f2f3', bestSan: 'e4');
      expect(v.quality, MoveQuality.blunder);
      expect(v.better, 'e4');
    });
  });

  group('PlayController', () {
    late Directory tmp;
    late FakeEngine engine;
    late ProviderContainer container;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('linedrill');
      engine = FakeEngine(_flat);
      container = ProviderContainer(overrides: [
        appDirProvider.overrideWith((ref) async => tmp),
        gamesProvider.overrideWith(_Games.new),
        engineProvider.overrideWith((ref) async => engine),
        randomProvider.overrideWithValue(math.Random(1)),
      ]);
      await container.read(gamesProvider.future);
      final repertoire = container.read(repertoireProvider.notifier);
      await container.read(repertoireProvider.future);
      await repertoire.setReference(Side.white, Chess.initial, 'e4', const []);
      final afterE5 = Chess.initial.play(Move.parse('e2e4')!).play(Move.parse('e7e5')!);
      await repertoire.setReference(Side.white, afterE5, 'Nf3', const ['e4', 'e5']);
    });

    tearDown(() async {
      container.dispose();
      await tmp.delete(recursive: true);
    });

    PlayState state() => container.read(playProvider);
    PlayController play() => container.read(playProvider.notifier);

    test('déroule le répertoire puis passe à Stockfish', () async {
      await play().start(Side.white, OpponentLevel.easy);
      expect(state().phase, PlayPhase.repertoire);
      expect(state().myTurn, isTrue);

      await play().play(Move.parse('e2e4')!);
      expect(state().moves.map((m) => m.san), ['e4', 'e5']);
      expect(state().lastVerdict!.quality, MoveQuality.book);

      await play().play(Move.parse('g1f3')!);
      // Nc6, la réponse de mes parties, puis fin du répertoire.
      expect(state().moves.map((m) => m.san), ['e4', 'e5', 'Nf3', 'Nc6']);
      expect(state().phase, PlayPhase.engine);
      expect(state().message, contains('Stockfish juge tes coups'));
      expect(engine.analysed, isEmpty);
    });

    test('corrige un écart au répertoire, puis rejouer', () async {
      await play().start(Side.white, OpponentLevel.easy);
      await play().play(Move.parse('d2d4')!);
      final pending = state().pending!;
      expect(pending.san, 'd4');
      expect(pending.verdict.better, 'e4');
      expect(pending.verdict.quality, MoveQuality.offBook);
      expect(state().myTurn, isFalse);

      play().retry();
      expect(state().pending, isNull);
      expect(state().position.fen, Chess.initial.fen);
      expect(state().corrections, 1);
      expect(state().myTurn, isTrue);
    });

    test('garder un écart au répertoire passe à Stockfish', () async {
      await play().start(Side.white, OpponentLevel.easy);
      await play().play(Move.parse('d2d4')!);
      await play().keep();
      expect(state().phase, PlayPhase.engine);
      expect(state().moves, hasLength(2));
      expect(state().myTurn, isTrue);
    });

    test('moteur en panne : la partie ne reste pas bloquée', () async {
      container.updateOverrides([
        appDirProvider.overrideWith((ref) async => tmp),
        gamesProvider.overrideWith(_Games.new),
        engineProvider.overrideWith((ref) async => FakeEngine((_, _) => throw StateError('panne'))),
        randomProvider.overrideWithValue(math.Random(1)),
      ]);
      await play().start(Side.white, OpponentLevel.easy);
      await play().play(Move.parse('e2e4')!);
      await play().play(Move.parse('g1f3')!);
      // Fin du répertoire : le coup suivant passe par le moteur, en panne.
      await play().play(Move.parse('f1c4')!);
      expect(state().thinking, isFalse);
      expect(state().pending, isNull);
      expect(state().message, contains('Stockfish indisponible'));
      expect(state().moves.last.san, 'Bc4');
    });

    test('Stockfish signale une gaffe et propose le meilleur coup', () async {
      engine = FakeEngine((p, multiPv) {
        // Après 1.e4 e5 2.Nf3 Nc6, laisser le cavalier f3 en prise coûte cher.
        if (p.turn == Side.white && p.fullmoves == 3) {
          return const [EngineLine('f1b5', 40), EngineLine('f1c4', 30), EngineLine('d2d4', 30)];
        }
        if (p.turn == Side.black && p.fullmoves == 3) return const [EngineLine('d8f6', 500)];
        return _flat(p, multiPv);
      });
      container.updateOverrides([
        appDirProvider.overrideWith((ref) async => tmp),
        gamesProvider.overrideWith(_Games.new),
        engineProvider.overrideWith((ref) async => engine),
        randomProvider.overrideWithValue(math.Random(1)),
      ]);
      await play().start(Side.white, OpponentLevel.easy);
      await play().play(Move.parse('e2e4')!);
      await play().play(Move.parse('g1f3')!);
      expect(state().phase, PlayPhase.engine);

      await play().play(Move.parse('f3g5')!);
      final pending = state().pending!;
      expect(pending.verdict.quality, MoveQuality.blunder);
      expect(pending.verdict.better, 'Bb5');

      play().retry();
      await play().play(Move.parse('f1b5')!);
      expect(state().pending, isNull);
      expect(state().moves.last.side, Side.black);
      expect(state().moves[state().moves.length - 2].quality, MoveQuality.good);
    });
  });
}
