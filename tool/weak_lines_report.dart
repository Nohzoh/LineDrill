// ignore_for_file: avoid_print
// Affiche les lignes faibles d'un PGN : dart run tool/weak_lines_report.dart <pgn> <pseudo>
import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:linedrill/core/opening_tree.dart';
import 'package:linedrill/core/pgn_import.dart';
import 'package:linedrill/core/weak_lines.dart';

void main(List<String> args) {
  final games = parseGames(File(args[0]).readAsStringSync(), args[1]);
  for (final color in Side.values) {
    final tree = OpeningTree.build(games, GameFilter(color: color));
    print('== ${color.name} (${tree.games.length} parties, ${(tree.score * 100).toStringAsFixed(1)} %)');
    for (final w in weakLines(tree)) {
      final s = w.stats;
      print('${w.cost.toStringAsFixed(1).padLeft(5)}  ${s.count.toString().padLeft(4)}  '
          '${(s.score * 100).toStringAsFixed(0).padLeft(3)} %  ${w.line.join(' ')}');
    }
  }
}
