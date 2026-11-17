// ignore_for_file: avoid_print
// Régénère assets/openings.tsv à partir des fichiers a.tsv … e.tsv de
// https://github.com/lichess-org/chess-openings (CC0) :
//   dart run tool/build_openings.dart <dossier des .tsv> > assets/openings.tsv
import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:linedrill/core/opening_tree.dart';
import 'package:linedrill/core/pgn_import.dart';

void main(List<String> args) {
  final files = Directory(args[0]).listSync().whereType<File>().where((f) => f.path.endsWith('.tsv')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final names = <String, String>{};
  var skipped = 0;
  var unreadable = 0;
  var collisions = 0;
  for (final file in files) {
    // Colonnes : eco, nom, coups (« 1. e4 d5 2. exd5 »).
    for (final row in file.readAsLinesSync().skip(1)) {
      final columns = row.split('\t');
      if (columns.length < 3) continue;
      final sans = columns[2].split(' ').where((t) => t.isNotEmpty && !t.endsWith('.')).toList();
      // L'arbre ne va pas plus loin : une position plus profonde ne serait jamais consultée.
      if (sans.length > maxPlies) {
        skipped++;
        continue;
      }
      Position? position = Chess.initial;
      for (final san in sans) {
        final move = position!.parseSan(san);
        position = move == null ? null : position.play(move);
        if (position == null) break;
      }
      if (position == null) {
        stderr.writeln('Coups illisibles : $row');
        unreadable++;
        continue;
      }
      // Deux ouvertures sur la même position : la première lue garde le nom.
      final key = positionKey(position);
      if (names.containsKey(key)) collisions++;
      names.putIfAbsent(key, () => columns[1]);
    }
  }
  // Rien n'est écrit : la sortie remplace d'habitude la table en place.
  if (unreadable > 0) {
    stderr.writeln('$unreadable ouvertures illisibles : table non générée.');
    exit(1);
  }
  final keys = names.keys.toList()..sort();
  for (final key in keys) {
    print('$key\t${names[key]}');
  }
  stderr.writeln('${names.length} positions nommées, $skipped ouvertures au-delà de $maxPlies demi-coups ignorées, '
      '$collisions positions à deux noms.');
}
