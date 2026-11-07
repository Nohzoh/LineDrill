import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/core/game_record.dart';
import 'package:linedrill/core/opening_tree.dart';
import 'package:linedrill/core/repertoire.dart';
import 'package:linedrill/data/repertoire_store.dart';

GameRecord _g(String moves, double score, {Side color = Side.white}) =>
    GameRecord(color: color, score: score, timeClass: TimeClass.bullet, sans: moves.split(' '));

String _key(String moves) {
  Position p = Chess.initial;
  for (final san in moves.isEmpty ? <String>[] : moves.split(' ')) {
    p = p.play(p.parseSan(san)!);
  }
  return positionKey(p);
}

RepertoireEntry _entry(String line, String san, {Side color = Side.white}) => RepertoireEntry(
      color: color,
      positionKey: _key(line),
      san: san,
      line: line.isEmpty ? const [] : line.split(' '),
    );

void main() {
  group('Repertoire', () {
    test('une entrée par position et par couleur', () {
      var r = Repertoire().withEntry(_entry('e4 g6', 'd4'));
      r = r.withEntry(_entry('e4 g6', 'Nf3'));
      expect(r.entries, hasLength(1));
      expect(r.lookup(Side.white, _key('e4 g6'))!.san, 'Nf3');
      expect(r.lookup(Side.black, _key('e4 g6')), isNull);
      expect(r.without(Side.white, _key('e4 g6')).entries, isEmpty);
    });

    test('JSON aller-retour', () {
      final r = Repertoire([_entry('', 'e4'), _entry('e4', 'c5', color: Side.black)]);
      final back = Repertoire.fromJson(r.toJson());
      expect(back.entries, hasLength(2));
      expect(back.lookup(Side.black, _key('e4'))!.san, 'c5');
      expect(back.lookup(Side.white, _key(''))!.line, isEmpty);
    });
  });

  group('repertoireUsage', () {
    test('compte les parties qui suivent ou dévient', () {
      final r = Repertoire([_entry('e4 g6', 'd4')]);
      final usage = repertoireUsage([
        _g('e4 g6 d4 Bg7', 1),
        _g('e4 g6 Nf3 Bg7', 0),
        _g('e4 g6 Nf3 Bg7', 0),
        _g('e4 e5 Nf3', 1),
      ], r)[r.entries.single.id]!;
      expect(usage.reached, 3);
      expect(usage.followed, hasLength(1));
      expect(usage.deviated.map((d) => d.played), ['Nf3', 'Nf3']);
      expect(usage.followedScore, 1);
      expect(usage.deviatedScore, 0);
    });

    test('suit les transpositions', () {
      final r = Repertoire([_entry('e4 e5 Nf3 Nc6', 'd4')]);
      final usage = repertoireUsage([_g('Nf3 Nc6 e4 e5 Bb5', 0.5)], r).values.single;
      expect(usage.deviated.single.played, 'Bb5');
    });

    test('s\'arrête à la première déviation', () {
      final r = Repertoire([_entry('', 'e4'), _entry('e4 e5', 'Nf3')]);
      final usage = repertoireUsage([_g('d4 d5 e4', 1)], r);
      expect(usage[r.lookup(Side.white, _key(''))!.id]!.deviated, hasLength(1));
      expect(usage[r.lookup(Side.white, _key('e4 e5'))!.id]!.reached, 0);
    });

    test('ignore les positions où c\'est à l\'adversaire de jouer', () {
      final r = Repertoire([_entry('', 'e4', color: Side.black)]);
      final usage = repertoireUsage([_g('d4 d5', 1, color: Side.black)], r).values.single;
      expect(usage.reached, 0);
    });
  });

  group('RepertoireStore', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('linedrill'));
    tearDown(() => tmp.delete(recursive: true));

    test('répertoire et jeton persistés', () async {
      final store = RepertoireStore(tmp);
      expect((await store.loadRepertoire()).entries, isEmpty);
      await store.saveRepertoire(Repertoire([_entry('e4 g6', 'd4')]));
      expect((await RepertoireStore(tmp).loadRepertoire()).entries.single.san, 'd4');

      expect(await store.lichessToken(), isNull);
      await store.setLichessToken('  lip_abc  ');
      expect(await store.lichessToken(), 'lip_abc');
      await store.setLichessToken('');
      expect(await store.lichessToken(), isNull);
    });
  });
}
