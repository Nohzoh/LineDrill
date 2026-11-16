// ignore_for_file: avoid_print
// Affiche le bilan des ouvertures d'un PGN : dart run tool/openings_report.dart <pgn> <pseudo>
import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:linedrill/core/opening_report.dart';
import 'package:linedrill/core/opening_tree.dart';
import 'package:linedrill/core/openings.dart';
import 'package:linedrill/core/pgn_import.dart';

void main(List<String> args) {
  final games = parseGames(File(args[0]).readAsStringSync(), args[1]);
  final book = OpeningBook.parse(File('assets/openings.tsv').readAsStringSync());
  for (final color in Side.values) {
    final tree = OpeningTree.build(games, GameFilter(color: color));
    final report = openingReport(tree, color: color, book: book);
    print('== ${color.name} (${tree.games.length} parties, variantes dès ${report.minGames} parties)');
    for (final family in report.families) {
      print('${family.name} · ${family.count} parties · ${(family.score * 100).round()} %');
      for (final v in family.variants) {
        final gap = v.gap;
        final reason = gap == null
            ? ''
            : '  [${gap.status.name} : ${gap.played.san} ${(gap.share * 100).round()} %'
                '${gap.reference == gap.played.san ? '' : ', à retenir ${gap.reference}'}]';
        print('  ${v.count.toString().padLeft(4)}  ${(v.score * 100).round().toString().padLeft(3)} %  '
            '${v.knownDepth}/${v.steps.length}  ${v.line.join(' ')}  (${v.name?.variation ?? '-'})$reason');
      }
    }
  }
}
