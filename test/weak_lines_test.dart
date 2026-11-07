import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/core/game_record.dart';
import 'package:linedrill/core/opening_tree.dart';
import 'package:linedrill/core/pgn_import.dart';
import 'package:linedrill/core/weak_lines.dart';

GameRecord _g(String moves, double score, {Side color = Side.white}) => GameRecord(
      color: color,
      score: score,
      timeClass: TimeClass.bullet,
      sans: moves.split(' '),
    );

List<GameRecord> _repeat(int n, String moves, double score) =>
    List.generate(n, (_) => _g(moves, score));

void main() {
  test('classe par points perdus sous la moyenne', () {
    final games = [
      ..._repeat(10, 'e4 e5 Nf3', 1), // 100 %
      ..._repeat(10, 'e4 c5 Nf3', 0), // 0 %
      ..._repeat(20, 'e4 e6 d4', 0.5), // 50 %
    ];
    final tree = OpeningTree.build(games, const GameFilter(color: Side.white));
    final lines = weakLines(tree, minGames: 5);
    expect(lines.first.line, ['e4', 'c5']);
    expect(lines.first.cost, closeTo(5, 0.001)); // (0,5 − 0) × 10
    expect(lines.map((l) => l.line.join(' ')), isNot(contains('e4')));
  });

  test('ignore les coups trop peu joués', () {
    final games = [..._repeat(9, 'e4 c5', 0), ..._repeat(9, 'e4 e5', 1)];
    final tree = OpeningTree.build(games, const GameFilter(color: Side.white));
    expect(weakLines(tree), isEmpty);
  });

  test('raccourcit une suite quasi forcée', () {
    final games = [
      ..._repeat(12, 'e4 g6 Nf3 Bg7', 0),
      ..._repeat(1, 'e4 g6 d4', 0),
      ..._repeat(13, 'e4 e5', 1),
    ];
    final tree = OpeningTree.build(games, const GameFilter(color: Side.white));
    expect(weakLines(tree).single.line, ['e4', 'g6']);
  });

  test('garde une sous-ligne nettement pire', () {
    final games = [
      ..._repeat(10, 'e4 d5 exd5 Qxd5 d4', 0.5),
      ..._repeat(10, 'e4 d5 exd5 Qxd5 Nc3', 0),
      ..._repeat(10, 'e4 d5 Nc3', 0.5),
      ..._repeat(30, 'e4 e5', 1),
    ];
    final tree = OpeningTree.build(games, const GameFilter(color: Side.white));
    final lines = weakLines(tree).map((l) => l.line.join(' ')).toList();
    expect(lines.first, 'e4 d5');
    expect(lines, contains('e4 d5 exd5 Qxd5 Nc3'));
    expect(lines, isNot(contains('e4 d5 Nc3')));
  });

  test('distingue mon coup et la réponse adverse', () {
    final line = WeakLine(['e4', 'g6'], MoveStats('g6', NormalMove.fromUci('g7g6'), ''), 1);
    expect(line.lastMoveIsOpponent(true), isTrue);
    expect(line.lastMoveIsOpponent(false), isFalse);
  });

  final refPath = Platform.environment['LINEDRILL_REF_PGN'];
  test('référence octobre 2026', () {
    final games = parseGames(File(refPath!).readAsStringSync(), 'Lappeau');
    List<String> top(Side color) => weakLines(OpeningTree.build(games, GameFilter(color: color)))
        .map((l) => l.line.join(' '))
        .toList();

    final white = top(Side.white);
    expect(white.first, 'e4 g6');
    expect(white.take(5), containsAll(['e4 c6', 'e4 d5 exd5 Qxd5 Nc3 Qd8', 'e4 d5 exd5 Qxd5 Nc3 Qe6+']));
    expect(white, contains('e4 e5 Nf3 Nc6 d4 Nf6'));

    final black = top(Side.black);
    expect(black, containsAll([
      'e4 d5 exd5 Qxd5 Nc3 Qa5 d4',
      'e4 d5 exd5 Qxd5 Nc3 Qa5 d4 c6 Bd2',
      'd4 d5 e3',
    ]));
  }, skip: refPath == null ? 'LINEDRILL_REF_PGN non défini' : false);
}
