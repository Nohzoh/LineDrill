import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/core/explain.dart';
import 'package:linedrill/engine/chess_engine.dart';

Position _after(String moves) {
  Position p = Chess.initial;
  for (final san in moves.split(' ')) {
    p = p.play(p.parseSan(san)!);
  }
  return p;
}

MoveExplanation _explain(String moves, String played, EngineLine best, List<String> refutation, int playedCp) {
  final before = _after(moves);
  return explainMove(
    before: before,
    move: before.parseSan(played)!,
    best: best,
    refutation: refutation,
    playedCp: playedCp,
  );
}

void main() {
  test('pièce que je viens de jouer, en prise', () {
    final e = _explain('e4 d6', 'Qg4', const EngineLine('d2d4', 40, ['d2d4', 'g8f6']),
        ['c8g4', 'h2h3', 'g4h5', 'd2d4'], -850);
    expect(e.consequences, [
      'Ta dame que tu viens de jouer en g4 n\'est pas assez défendue.',
      'Au bout de la suite, tu perds une dame.',
    ]);
    expect(e.refutation, '2… Bxg4 3. h3 Bh5 4. d4');
    expect(e.threat, NormalMove.fromUci('c8g4'));
  });

  test('pièce déjà attaquée, échange compensé', () {
    final e = _explain('e4 e5 Nf3 Nc6 Bc4 Nf6', 'a3', const EngineLine('d2d3', 30, ['d2d3']),
        ['f6e4', 'b1c3', 'e4c3', 'd2c3'], -60);
    expect(e.consequences, [
      'Ton pion en e4 était attaqué et tu ne l\'as pas mis à l\'abri.',
      'Au bout de la suite, tu perds un pion.',
    ]);
  });

  test('mat raté et matériel gagnable', () {
    final mate = _explain('e4 e5 Qh5 Nc6 Bc4 Nf6', 'd3', EngineLine('h5f7', mateScore(1), const ['h5f7']),
        ['f6h5'], -900);
    expect(mate.missed, ['Tu avais un mat immédiat : Qxf7#.']);

    final queen = _explain('e4 e5 Nf3 Qh4', 'd4', const EngineLine('f3h4', 900, ['f3h4', 'd7d5']),
        ['h4e4', 'f1e2', 'e4f5', 'd4e5'], 100);
    expect(queen.missed, ['Nxh4 gagnait une dame.']);
    expect(queen.consequences.single, startsWith('La position se dégrade : d\'un avantage décisif pour toi (+9,0)'));
  });

  test('mat subi', () {
    // 1.f3 e5 2.g4?? Qh4#
    final e = _explain('f3 e5', 'g4', const EngineLine('e2e4', -50, ['e2e4']), ['d8h4'], mateScore(-1));
    expect(e.consequences, ['L\'adversaire a un mat immédiat : 2… Qh4#.']);
  });

  test('fourchette permise', () {
    // 1.e4 e5 2.Nf3 Nc6 3.Bc4 Nf6 4.Ng5 d5 5.exd5 Nxd5?! : 6.Nxf7 attaque dame et tour.
    final e = _explain('e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 d5 exd5', 'Nxd5', const EngineLine('c6a5', 0, ['c6a5']),
        ['g5f7', 'e8f7'], -150);
    expect(e.consequences.first, contains('attaque à la fois ta dame (d8) et ta tour (h8)'));
  });

  test('roque perdu', () {
    final e = _explain('e4 e5', 'Ke2', const EngineLine('g1f3', 40, ['g1f3']), ['g8f6', 'b1c3'], -60);
    expect(e.consequences, ['Tu perds le droit de roquer : ton roi restera exposé.']);
  });

  test('pas de gain annoncé sans avantage réel', () {
    // 1.e4 e5 2.Ba6?? : la ligne de Nf3 peut finir sur un échange coupé.
    final e = _explain('e4 e5', 'Ba6', const EngineLine('g1f3', 40, ['g1f3', 'b8c6', 'f1b5', 'g8f6', 'b5c6', 'd7c6', 'f3e5']),
        ['b8a6', 'g1f3', 'd7d6', 'd2d4'], -280);
    expect(e.missed, isEmpty);
    expect(e.consequences.first, 'Ton fou que tu viens de jouer en a6 n\'est pas assez défendu.');
  });

  test('sans motif : évolution de l\'évaluation', () {
    final e = _explain('e4 e5 Nf3 Nc6', 'h3', const EngineLine('d2d4', 45, ['d2d4']), ['g8f6', 'b1c3'], -20);
    expect(e.consequences, ['La position se dégrade : d\'un léger avantage pour toi (+0,5) à l\'égalité (−0,2).']);
    expect(e.missed, isEmpty);
  });
}
