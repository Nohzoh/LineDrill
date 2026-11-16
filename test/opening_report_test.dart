import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/core/game_record.dart';
import 'package:linedrill/core/opening_report.dart';
import 'package:linedrill/core/opening_tree.dart';
import 'package:linedrill/core/openings.dart';
import 'package:linedrill/core/repertoire.dart';

List<GameRecord> _repeat(int n, String moves, double score, {Side color = Side.white}) => List.generate(
      n,
      (_) => GameRecord(color: color, score: score, timeClass: TimeClass.bullet, sans: moves.split(' ')),
    );

String _key(String moves) {
  Position p = Chess.initial;
  for (final san in moves.isEmpty ? <String>[] : moves.split(' ')) {
    p = p.play(p.parseSan(san)!);
  }
  return positionKey(p);
}

OpeningBook _book(Map<String, String> names) => OpeningBook({for (final e in names.entries) _key(e.key): e.value});

OpeningReport _report(
  List<GameRecord> games, {
  Side color = Side.white,
  OpeningBook book = OpeningBook.empty,
  Repertoire? repertoire,
  int minGames = 5,
}) =>
    openingReport(
      OpeningTree.build(games, GameFilter(color: color)),
      color: color,
      book: book,
      repertoire: repertoire,
      minGames: minGames,
    );

void main() {
  group('OpeningBook', () {
    test('lit la table et sépare famille et variante', () {
      final book = OpeningBook.parse('a b c d\tScandinavian Defense: Mieses-Kotrč Variation\nx y z w\tItalian Game\n\n');
      expect(book.length, 2);
      expect(book.nameOf('a b c d')!.family, 'Scandinavian Defense');
      expect(book.nameOf('a b c d')!.variation, 'Mieses-Kotrč Variation');
      expect(book.nameOf('x y z w')!.family, 'Italian Game');
      expect(book.nameOf('x y z w')!.variation, isNull);
      expect(book.nameOf('inconnue'), isNull);
    });

    test('la table embarquée nomme les positions de l\'arbre', () async {
      // Par le bundle, comme l'appli : la table doit rester déclarée dans le pubspec.
      TestWidgetsFlutterBinding.ensureInitialized();
      final book = OpeningBook.parse(await rootBundle.loadString('assets/openings.tsv'));
      expect(book.length, greaterThan(3000));
      expect(book.nameOf(_key('e4 d5'))!.full, 'Scandinavian Defense');
      expect(book.nameOf(_key('e4 d5 exd5 Qxd5 Nc3 Qa5'))!.family, 'Scandinavian Defense');
      expect(book.nameOf(_key('e4 e5 Nf3 Nc6 Bc4'))!.full, 'Italian Game');
      // Même position par un autre ordre de coups : même nom.
      expect(book.nameOf(_key('Nf3 Nc6 e4 e5 Bc4'))!.full, 'Italian Game');
    });
  });

  group('openingReport', () {
    test('une variante par réponse adverse assez jouée, coups connus d\'affilée', () {
      final report = _report(
        [
          ..._repeat(12, 'e4 d5 exd5 Qxd5 Nc3 Qa5 d4', 1),
          ..._repeat(6, 'e4 d5 exd5 Qxd5 Nc3 Qd8 d4', 0),
          ..._repeat(5, 'e4 d5 exd5 Qxd5 Nc3 Qd8 Nf3', 1),
          ..._repeat(4, 'e4 g6', 0),
        ],
        book: _book({
          'e4': 'King\'s Pawn Game',
          'e4 d5': 'Scandinavian Defense',
          'e4 d5 exd5 Qxd5 Nc3 Qa5': 'Scandinavian Defense: Main Line',
        }),
      );

      final family = report.families.single;
      expect(family.name, 'Scandinavian Defense');
      expect(family.count, 23);
      expect(family.score, closeTo(17 / 23, 0.001));

      final [mainLine, qd8] = family.variants;
      expect(mainLine.name!.variation, 'Main Line');
      expect(mainLine.line.join(' '), 'e4 d5 exd5 Qxd5 Nc3 Qa5 d4');
      expect(mainLine.count, 12);
      expect(mainLine.steps.map((s) => s.reference), ['e4', 'exd5', 'Nc3', 'd4']);
      expect(mainLine.knownDepth, 4);
      expect(mainLine.gap, isNull);

      // Après 3… Qd8, deux coups à peu près aussi joués : pas d'habitude.
      // La variante suit le plus joué et ne compte que ses parties.
      expect(qd8.name!.variation, isNull);
      expect(qd8.line.join(' '), 'e4 d5 exd5 Qxd5 Nc3 Qd8 d4');
      expect(qd8.count, 6);
      expect(qd8.score, 0);
      expect(qd8.knownDepth, 3);
      final gap = qd8.gap!;
      expect(gap.status, HabitStatus.hesitant);
      expect(gap.line.join(' '), 'e4 d5 exd5 Qxd5 Nc3 Qd8');
      expect(gap.played.san, 'd4');
      expect(gap.alternative!.san, 'Nf3');
      expect(gap.share, closeTo(6 / 11, 0.001));
    });

    test('le coup du répertoire est celui à retenir, la variante reste celle que je joue', () {
      final games = [..._repeat(8, 'e4 e5 Bc4 Nc6', 0), ..._repeat(2, 'e4 e5 Nf3 Nc6', 1)];
      RepertoireEntry star(String san) =>
          RepertoireEntry(color: Side.white, positionKey: _key('e4 e5'), san: san, line: const ['e4', 'e5']);

      // Coup de référence peu joué, ou jamais : signalé, sans cacher ce que je joue.
      for (final san in ['Nf3', 'd4']) {
        final variant = _report(games, repertoire: Repertoire([star(san)])).families.single.variants.single;
        expect(variant.line.join(' '), 'e4 e5 Bc4 Nc6');
        expect(variant.count, 8);
        expect(variant.knownDepth, 1);
        expect(variant.gap!.status, HabitStatus.offRepertoire);
        expect(variant.gap!.reference, san);
        expect(variant.gap!.played.san, 'Bc4');
      }

      // Coup de référence qui est aussi mon habitude : acquis.
      final same = _report(games, repertoire: Repertoire([star('Bc4')])).families.single.variants.single;
      expect(same.knownDepth, 2);
    });

    test('un coup du répertoire assez joué est suivi, même s\'il n\'est pas le plus joué', () {
      final variant = _report(
        [..._repeat(8, 'e4 e5 Bc4 Nc6', 0), ..._repeat(6, 'e4 e5 Nf3 Nc6', 1)],
        repertoire: Repertoire([
          RepertoireEntry(color: Side.white, positionKey: _key('e4 e5'), san: 'Nf3', line: const ['e4', 'e5']),
        ]),
      ).families.single.variants.single;
      expect(variant.line.join(' '), 'e4 e5 Nf3 Nc6');
      expect(variant.count, 6);
      expect(variant.gap!.status, HabitStatus.offRepertoire);
    });

    test('Noirs : une variante par premier coup adverse assez joué', () {
      final report = _report(
        [
          ..._repeat(6, 'e4 d5', 1, color: Side.black),
          ..._repeat(5, 'd4 d5', 0, color: Side.black),
          ..._repeat(2, 'c4 e5', 1, color: Side.black),
        ],
        color: Side.black,
        book: _book({'e4 d5': 'Scandinavian Defense', 'd4 d5': 'Queen\'s Pawn Game'}),
      );
      expect(report.families.map((f) => f.name), ['Scandinavian Defense', 'Queen\'s Pawn Game']);
      expect(report.families.first.variants.single.steps.single.reference, 'd5');
      expect(report.families.first.variants.single.knownDepth, 1);
    });

    test('deux ordres de coups qui se rejoignent : une seule variante, parties comptées une fois', () {
      final family = _report([
        ..._repeat(7, 'e4 e5 Nc3 Nf6 Bc4 Nc6 d3', 1),
        ..._repeat(5, 'e4 e5 Nc3 Nc6 Bc4 Nf6 d3', 0),
      ]).families.single;
      // Après 3… Nc6 ou 3… Nf6, même position : 12 parties y jouent 4. d3.
      final variant = family.variants.single;
      expect(variant.line.join(' '), 'e4 e5 Nc3 Nf6 Bc4 Nc6 d3');
      expect(variant.count, 12);
      expect(family.count, 12);
      expect(family.score, closeTo(7 / 12, 0.001));
    });

    test('entre deux ordres de coups, celui du chemin le plus joué est gardé', () {
      final report = _report(
        [
          ..._repeat(6, 'e4 e6 d4 d5', 1, color: Side.black),
          ..._repeat(60, 'e4 e6 Nf3 d5', 1, color: Side.black),
          ..._repeat(50, 'd4 e6 e4 d5', 0, color: Side.black),
          ..._repeat(10, 'd4 e6 c4 d5', 1, color: Side.black),
        ],
        color: Side.black,
      );
      final lines = {for (final v in report.families.single.variants) v.line.join(' '): v.count};
      expect(lines, {'e4 e6 Nf3 d5': 60, 'd4 e6 e4 d5': 56, 'd4 e6 c4 d5': 10});
    });

    test('une ouverture compte aussi les parties qui quittent ses variantes', () {
      final family = _report(
        [
          ..._repeat(30, 'e4 c5 Nf3 d6', 1),
          ..._repeat(20, 'e4 c5 Nf3 Nc6', 0),
          ..._repeat(4, 'e4 c5 Nf3 e6', 0),
          ..._repeat(40, 'e4 c5 c3 d5', 0),
          ..._repeat(3, 'd4 d5', 1),
        ],
        book: _book({'e4 c5': 'Sicilian Defense', 'd4': 'Queen\'s Pawn Game'}),
        minGames: 10,
      ).families.single;
      expect(family.name, 'Sicilian Defense');
      expect(family.variants.map((v) => v.count), [30, 20]);
      // Les 2. c3 et la réponse rare 2… e6 restent des Siciliennes ; 1. d4 non.
      expect(family.count, 94);
      expect(family.score, closeTo(30 / 94, 0.001));
    });

    test('à égalité, le coup du répertoire est mon coup habituel', () {
      final step = _report(
        [..._repeat(5, 'e4 e5 Bc4', 1), ..._repeat(5, 'e4 e5 Nf3', 1)],
        repertoire: Repertoire([
          RepertoireEntry(color: Side.white, positionKey: _key('e4 e5'), san: 'Nf3', line: const ['e4', 'e5']),
        ]),
      ).families.single.variants.single.gap!;
      expect(step.status, HabitStatus.hesitant);
      expect(step.played.san, 'Nf3');
      expect(step.alternative!.san, 'Bc4');
    });

    test('coup de référence jamais joué au premier coup : signalé, pas un bilan vide', () {
      final variant = _report(
        _repeat(8, 'e4 e5', 1),
        repertoire: Repertoire([
          RepertoireEntry(color: Side.white, positionKey: _key(''), san: 'd4', line: const []),
        ]),
      ).families.single.variants.single;
      expect(variant.line, ['e4', 'e5']);
      expect(variant.count, 8);
      expect(variant.knownDepth, 0);
      expect(variant.gap!.status, HabitStatus.offRepertoire);
      expect(variant.gap!.reference, 'd4');
    });

    test('un coup joué 6 fois sur 10 au pour cent près est acquis', () {
      // 28 sur 47 : 59,6 %, affiché 60 %.
      final games = [..._repeat(28, 'e4 e5', 1), ..._repeat(19, 'd4 d5', 1)];
      expect(_report(games).families.first.variants.single.steps.single.status, HabitStatus.known);
    });

    test('sans table des noms : tout est rangé dans une même famille', () {
      final report = _report([..._repeat(6, 'e4 e5', 1), ..._repeat(5, 'e4 c5', 0)]);
      expect(report.families.single.name, unnamedFamily);
      expect(report.families.single.variants, hasLength(2));
    });

    test('trop peu de parties : bilan vide', () {
      expect(_report(_repeat(4, 'e4 e5 Nf3', 1)).families, isEmpty);
      expect(_report(_repeat(4, 'e4 e5', 1, color: Side.black), color: Side.black).families, isEmpty);
    });

    test('une répétition de coups ne fait pas tourner en rond', () {
      final variant = _report(_repeat(6, 'Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1 Ng8', 0.5)).families.single.variants.single;
      expect(variant.line, ['Nf3', 'Nf6', 'Ng1']);
      expect(variant.steps, hasLength(2));
    });

    test('seuil de parties selon le volume', () {
      expect(habitMinGames(0), 5);
      expect(habitMinGames(300), 5);
      expect(habitMinGames(450), 8);
      expect(habitMinGames(661), 10);
      expect(_report(_repeat(661, 'e4', 1), minGames: 7).minGames, 7);
      // Un seuil nul ne fait pas chercher un coup là où aucune partie ne continue.
      expect(_report(_repeat(2, 'e4 e5', 1), minGames: 0).families.single.variants.single.line, ['e4', 'e5']);
    });
  });
}
