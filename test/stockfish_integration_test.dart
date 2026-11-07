import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/app/play_controller.dart';
import 'package:linedrill/app/providers.dart';
import 'package:linedrill/core/training.dart';
import 'package:linedrill/engine/chess_engine.dart';

/// Stockfish de bureau : LINEDRILL_STOCKFISH=chemin/vers/stockfish flutter test
Future<ChessEngine> _desktopStockfish(String path) async {
  final process = await Process.start(path, const []);
  final engine = UciEngine(
    output: process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    send: (line) => process.stdin.writeln(line),
    onDispose: () async {
      process.stdin.writeln('quit');
      await process.exitCode;
    },
  );
  process.stdin.writeln('uci');
  return engine;
}

class _NoGames extends GamesNotifier {
  @override
  Future<GamesState> build() async => const GamesState(username: 'me');
}

void main() {
  final path = Platform.environment['LINEDRILL_STOCKFISH'];

  group('Stockfish réel', () {
    late ChessEngine engine;
    setUp(() async => engine = await _desktopStockfish(path!));
    tearDown(() => engine.dispose());

    test('analyse multi-lignes', () async {
      final lines = await engine.analyse(Chess.initial.fen, depth: 10, multiPv: 3);
      expect(lines, hasLength(3));
      expect(lines.first.cp, greaterThanOrEqualTo(lines.last.cp));
    });

    test('voit le mat en un', () async {
      // Mat du berger : Dxf7#.
      const fen = 'r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4';
      final lines = await engine.analyse(fen, depth: 8);
      expect(lines.first.uci, 'h5f7');
      expect(lines.first.cp, mateScore(1));
    });

    test('juge mes coups', () async {
      // 1.e4 d6 : 2.Qg4?? donne la dame au fou c8, 2.d4 est normal.
      final before = Chess.fromSetup(
        Setup.parseFen('rnbqkbnr/ppp1pppp/3p4/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2'),
      );
      final blunder = await judgeMove(engine, before, Move.parse('d1g4')!, depth: 10);
      expect(blunder.quality, MoveQuality.blunder);
      expect(blunder.better, isNotNull);
      final fine = await judgeMove(engine, before, Move.parse('d2d4')!, depth: 10);
      expect(fine.quality.needsCorrection, isFalse);
    });

    test('reconnaît le roque quelle que soit sa notation', () async {
      // Italienne : le roque est le meilleur coup ou presque.
      final before = Chess.fromSetup(Setup.parseFen(
        'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5',
      ));
      for (final uci in ['e1g1', 'e1h1']) {
        final verdict = await judgeMove(engine, before, Move.parse(uci)!, depth: 10);
        expect(verdict.quality.needsCorrection, isFalse, reason: uci);
      }
      expect(before.makeSan(engineMove(before, 'e1g1')).$2, 'O-O');
    });

    test('partie corrigée contre Stockfish, sans répertoire', () async {
      final tmp = await Directory.systemTemp.createTemp('linedrill');
      addTearDown(() => tmp.delete(recursive: true));
      final container = ProviderContainer(overrides: [
        appDirProvider.overrideWith((ref) async => tmp),
        gamesProvider.overrideWith(_NoGames.new),
        engineProvider.overrideWith((ref) async => engine),
        randomProvider.overrideWithValue(math.Random(2)),
      ]);
      addTearDown(container.dispose);
      await container.read(gamesProvider.future);
      await container.read(repertoireProvider.future);
      final play = container.read(playProvider.notifier);

      await play.start(Side.black, OpponentLevel.easy);
      final first = container.read(playProvider);
      expect(first.phase, PlayPhase.engine);
      expect(first.moves, hasLength(1));
      expect(first.myTurn, isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, skip: path == null ? 'LINEDRILL_STOCKFISH non défini' : false);
}
