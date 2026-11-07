import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/core/game_record.dart';
import 'package:linedrill/core/opening_tree.dart';
import 'package:linedrill/core/pgn_import.dart';

const _pgn = '''
[Event "Live Chess"]
[White "Lappeau"]
[Black "Someone"]
[Result "1-0"]
[TimeControl "60"]
[Link "https://www.chess.com/game/live/1"]

1. e4 {[%clk 0:00:59]} 1... e5 2. Nf3 Nc6 3. d4 exd4 4. Nxd4 Nxd4 5. Qxd4 1-0

[Event "Live Chess"]
[White "Other"]
[Black "LAPPEAU"]
[Result "1-0"]
[TimeControl "180+2"]

1. e4 d5 2. exd5 Qxd5 3. Nc3 Qa5 1-0

[Event "Live Chess"]
[White "Lappeau"]
[Black "Third"]
[Result "1/2-1/2"]
[TimeControl "600"]

1. Nf3 Nc6 2. e4 e5 1/2-1/2

[Event "Live Chess"]
[White "Lappeau"]
[Black "Fourth"]
[Result "0-1"]
[Variant "Chess960"]
[TimeControl "60"]

1. e4 e5 0-1

[Event "Live Chess"]
[White "Nobody"]
[Black "Else"]
[Result "1-0"]

1. d4 1-0
''';

void main() {
  group('TimeClass', () {
    test('classe les cadences', () {
      expect(TimeClass.fromTimeControl('60'), TimeClass.bullet);
      expect(TimeClass.fromTimeControl('120+1'), TimeClass.bullet);
      expect(TimeClass.fromTimeControl('120+2'), TimeClass.blitz);
      expect(TimeClass.fromTimeControl('180'), TimeClass.blitz);
      expect(TimeClass.fromTimeControl('180+2'), TimeClass.blitz);
      expect(TimeClass.fromTimeControl('600'), TimeClass.rapid);
      expect(TimeClass.fromTimeControl('1/86400'), TimeClass.other);
      expect(TimeClass.fromTimeControl(null), TimeClass.other);
    });
  });

  test('Ending', () {
    expect(Ending.fromTermination('Lappeau won on time'), Ending.time);
    expect(Ending.fromTermination('x won by checkmate'), Ending.checkmate);
    expect(Ending.fromTermination('x won by resignation'), Ending.resignation);
    expect(Ending.fromTermination('x won - game abandoned'), Ending.abandoned);
    expect(Ending.fromTermination('Game drawn by timeout vs insufficient material'), Ending.draw);
    expect(Ending.fromTermination('Game drawn by repetition'), Ending.draw);
    expect(Ending.fromTermination(null), Ending.other);
  });

  group('parseGames', () {
    final games = parseGames(_pgn, 'lappeau');

    test('garde les parties standard de l\'utilisateur', () {
      expect(games, hasLength(3));
    });

    test('couleur, score et cadence du point de vue de l\'utilisateur', () {
      expect(games[0].color, Side.white);
      expect(games[0].score, 1);
      expect(games[0].timeClass, TimeClass.bullet);
      expect(games[0].link, 'https://www.chess.com/game/live/1');
      expect(games[1].color, Side.black);
      expect(games[1].score, 0);
      expect(games[1].timeClass, TimeClass.blitz);
      expect(games[2].score, 0.5);
    });

    test('coups en SAN, commentaires ignorés', () {
      expect(games[0].sans, ['e4', 'e5', 'Nf3', 'Nc6', 'd4', 'exd4', 'Nxd4', 'Nxd4', 'Qxd4']);
    });

    test('16 demi-coups au maximum', () {
      final long = parseGames(
        '[White "a"]\n[Black "b"]\n[Result "1-0"]\n\n'
        '1. Nf3 Nf6 2. Ng1 Ng8 3. Nf3 Nf6 4. Ng1 Ng8 5. Nf3 Nf6 6. Ng1 Ng8 '
        '7. Nf3 Nf6 8. Ng1 Ng8 9. Nf3 Nf6 1-0',
        'a',
      );
      expect(long.single.sans, hasLength(maxPlies));
    });
  });

  group('OpeningTree', () {
    final games = parseGames(_pgn, 'lappeau');

    test('filtre par couleur et cadence', () {
      final white = OpeningTree.build(games, const GameFilter(color: Side.white));
      expect(white.games, hasLength(2));
      final whiteBullet = OpeningTree.build(
        games,
        const GameFilter(color: Side.white, timeClasses: {TimeClass.bullet}),
      );
      expect(whiteBullet.games, hasLength(1));
    });

    test('statistiques par coup', () {
      final tree = OpeningTree.build(games, const GameFilter(color: Side.white));
      final moves = tree.root.moves;
      expect(moves.map((m) => m.san), containsAll(['e4', 'Nf3']));
      final e4 = tree.root.move('e4')!;
      expect(e4.count, 1);
      expect(e4.score, 1);
      expect(tree.score, 0.75);
    });

    test('fusionne les transpositions', () {
      final tree = OpeningTree.build(games, const GameFilter(color: Side.white));
      final viaE4 = tree.follow(['e4', 'e5', 'Nf3', 'Nc6'])!;
      final viaNf3 = tree.follow(['Nf3', 'Nc6', 'e4', 'e5'])!;
      expect(viaE4.key, viaNf3.key);
      expect(viaE4.moves.single.san, 'd4');
    });
  });

  // Données réelles : LINEDRILL_REF_PGN=chemin/vers/ChessCom_lappeau_202610.pgn
  final refPath = Platform.environment['LINEDRILL_REF_PGN'];
  group('référence octobre 2026', () {
    late List<GameRecord> games;
    setUpAll(() => games = parseGames(File(refPath!).readAsStringSync(), 'Lappeau'));

    double scoreOf(Side color, List<String> line) {
      final tree = OpeningTree.build(games, GameFilter(color: color));
      final parent = tree.follow(line.sublist(0, line.length - 1))!;
      return parent.move(line.last)!.score;
    }

    int countOf(Side color, List<String> line) {
      final tree = OpeningTree.build(games, GameFilter(color: color));
      final parent = tree.follow(line.sublist(0, line.length - 1))!;
      return parent.move(line.last)!.count;
    }

    test('totaux', () {
      expect(games, hasLength(1322));
      expect(games.every((g) => g.timeClass == TimeClass.bullet), isTrue);
      final all = games.fold<double>(0, (s, g) => s + g.score) / games.length;
      expect(all, closeTo(0.506, 0.001));
      expect(OpeningTree.build(games, const GameFilter(color: Side.white)).score,
          closeTo(0.485, 0.001));
      expect(OpeningTree.build(games, const GameFilter(color: Side.black)).score,
          closeTo(0.526, 0.001));
    });

    test('lignes faibles', () {
      expect(countOf(Side.white, ['e4', 'g6']), 26);
      expect(scoreOf(Side.white, ['e4', 'g6']), closeTo(0.25, 0.005));
      expect(countOf(Side.white, ['e4', 'c6']), 50);
      expect(scoreOf(Side.white, ['e4', 'c6']), closeTo(0.41, 0.005));
      expect(countOf(Side.white, ['e4', 'd5', 'exd5', 'Qxd5', 'Nc3', 'Qd8']), 35);
      expect(scoreOf(Side.white, ['e4', 'd5', 'exd5', 'Qxd5', 'Nc3', 'Qd8']), closeTo(0.40, 0.005));
      // 27 parties dans cet ordre de coups, 30 avec les transpositions
      // (ex. 3.d4 Qa5 4.Nc3 c6) que l'arbre fusionne.
      expect(countOf(Side.black, ['e4', 'd5', 'exd5', 'Qxd5', 'Nc3', 'Qa5', 'd4', 'c6']), 30);
      expect(scoreOf(Side.black, ['e4', 'd5', 'exd5', 'Qxd5', 'Nc3', 'Qa5', 'd4', 'c6']),
          closeTo(0.417, 0.005));
      expect(countOf(Side.black, ['d4', 'd5', 'e3']), 21);
    });
  }, skip: refPath == null ? 'LINEDRILL_REF_PGN non défini' : false);
}
