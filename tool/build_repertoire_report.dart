// ignore_for_file: avoid_print
// Prépare un répertoire avec un Stockfish de bureau :
// dart run tool/build_repertoire_report.dart <pgn> <pseudo> <stockfish> [white|black]
import 'dart:convert';
import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:linedrill/core/opening_tree.dart';
import 'package:linedrill/core/pgn_import.dart';
import 'package:linedrill/core/repertoire_builder.dart';
import 'package:linedrill/engine/chess_engine.dart';

Future<void> main(List<String> args) async {
  final games = parseGames(File(args[0]).readAsStringSync(), args[1]);
  final process = await Process.start(args[2], const []);
  final engine = UciEngine(
    output: process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    send: (l) => process.stdin.writeln(l),
  );
  process.stdin.writeln('uci');
  final colors = args.length > 3 ? [Side.values.byName(args[3])] : Side.values;
  for (final color in colors) {
    final tree = OpeningTree.build(games, GameFilter(color: color));
    final watch = Stopwatch()..start();
    final proposals = await buildRepertoire(tree: tree, engine: engine, color: color);
    print('== ${color.name} : ${proposals.length} positions en ${watch.elapsed.inSeconds} s');
    for (final p in proposals) {
      final tag = switch (p.status) {
        ProposalStatus.kept => '  ',
        ProposalStatus.review => '?!',
        ProposalStatus.corrected => '✗ ',
      };
      final change = p.status == ProposalStatus.corrected ? ' (au lieu de ${p.usualSan})' : '';
      print('$tag ${p.line.join(' ').padRight(40)} → ${p.san}$change  [${p.usualCount}/${p.reached}]');
      if (p.status == ProposalStatus.corrected) {
        for (final r in [...?p.verdict.explanation?.consequences, ...?p.verdict.explanation?.missed]) {
          print('      · $r');
        }
      }
    }
  }
  process.stdin.writeln('quit');
  await process.exitCode;
}
