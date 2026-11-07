import 'dart:io';

import 'chesscom_client.dart';

/// Stockage local des PGN mensuels bruts, un fichier par mois.
///
/// Les PGN sont la source de vérité : l'arbre est reconstruit à partir
/// d'eux au chargement.
class GameStore {
  GameStore(this.root);

  final Directory root;

  File get _userFile => File('${root.path}/username.txt');

  Directory get _pgnDir => Directory('${root.path}/pgn');

  File _monthFile(ArchiveMonth m) => File('${_pgnDir.path}/${m.key}.pgn');

  Future<String?> username() async {
    if (!await _userFile.exists()) return null;
    final value = (await _userFile.readAsString()).trim();
    return value.isEmpty ? null : value;
  }

  /// Enregistre le pseudo ; un changement de pseudo efface les parties.
  Future<void> setUsername(String name) async {
    final current = await username();
    if (current != null && current.toLowerCase() != name.toLowerCase()) {
      await clearGames();
    }
    await root.create(recursive: true);
    await _userFile.writeAsString(name);
  }

  Future<List<ArchiveMonth>> storedMonths() async {
    if (!await _pgnDir.exists()) return [];
    final months = <ArchiveMonth>[];
    await for (final entity in _pgnDir.list()) {
      final name = entity.uri.pathSegments.last;
      final match = RegExp(r'^(\d{4})-(\d{2})\.pgn$').firstMatch(name);
      if (match != null) {
        months.add(ArchiveMonth(int.parse(match[1]!), int.parse(match[2]!)));
      }
    }
    months.sort();
    return months;
  }

  Future<String> readMonth(ArchiveMonth month) => _monthFile(month).readAsString();

  Future<void> writeMonth(ArchiveMonth month, String pgn) async {
    await _pgnDir.create(recursive: true);
    await _monthFile(month).writeAsString(pgn);
  }

  Future<void> deleteMonth(ArchiveMonth month) async {
    final file = _monthFile(month);
    if (await file.exists()) await file.delete();
  }

  Future<void> clearGames() async {
    if (await _pgnDir.exists()) await _pgnDir.delete(recursive: true);
  }
}
