import 'dart:convert';
import 'dart:io';

import '../core/drill.dart';
import '../core/repertoire.dart';

/// Répertoire et réglages, stockés en JSON dans le dossier de l'appli.
class RepertoireStore {
  RepertoireStore(this.root);

  final Directory root;

  File get _repertoireFile => File('${root.path}/repertoire.json');

  File get _tokenFile => File('${root.path}/lichess_token.txt');

  File get _settingsFile => File('${root.path}/settings.json');

  File get _drillFile => File('${root.path}/drill.json');

  // Lectures synchrones : ces fichiers ne font que quelques Ko.
  Future<Repertoire> loadRepertoire() async {
    if (!_repertoireFile.existsSync()) return Repertoire();
    return Repertoire.fromJson(jsonDecode(_repertoireFile.readAsStringSync()) as List<Object?>);
  }

  /// Écrit dans un fichier temporaire puis le renomme, pour ne jamais
  /// laisser un répertoire à moitié écrit.
  Future<void> saveRepertoire(Repertoire repertoire) async {
    await root.create(recursive: true);
    final tmp = File('${_repertoireFile.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(repertoire.toJson()));
    await tmp.rename(_repertoireFile.path);
  }

  Future<String?> lichessToken() async {
    if (!_tokenFile.existsSync()) return null;
    final token = _tokenFile.readAsStringSync().trim();
    return token.isEmpty ? null : token;
  }

  Future<void> setLichessToken(String? token) async {
    final value = token?.trim() ?? '';
    if (value.isEmpty) {
      if (await _tokenFile.exists()) await _tokenFile.delete();
      return;
    }
    await root.create(recursive: true);
    await _tokenFile.writeAsString(value);
  }

  /// Préférences (affichage, partie corrigée), en JSON libre.
  ///
  /// Un fichier illisible est traité comme vide plutôt que de bloquer l'appli.
  Future<Map<String, Object?>> settings() async {
    await _settingsQueue;
    return _readSettings();
  }

  Map<String, Object?> _readSettings() {
    if (!_settingsFile.existsSync()) return {};
    try {
      return (jsonDecode(_settingsFile.readAsStringSync()) as Map).cast<String, Object?>();
    } on FormatException {
      return {};
    }
  }

  /// Écritures des réglages, une à la fois : chaque modification relit le
  /// fichier à jour, pour ne pas écraser une modification concurrente.
  Future<void> _settingsQueue = Future.value();

  /// Remplace la clé [key] des réglages par [value].
  Future<void> updateSetting(String key, Object? value) {
    final write = _settingsQueue.then((_) async {
      await root.create(recursive: true);
      final next = {..._readSettings(), key: value};
      final tmp = File('${_settingsFile.path}.tmp');
      await tmp.writeAsString(jsonEncode(next));
      await tmp.rename(_settingsFile.path);
    });
    _settingsQueue = write.catchError((Object _) {});
    return write;
  }

  /// État des révisions (répétition espacée).
  Future<DrillDeck> loadDeck() async {
    if (!_drillFile.existsSync()) return DrillDeck();
    return DrillDeck.fromJson((jsonDecode(_drillFile.readAsStringSync()) as Map).cast<String, Object?>());
  }

  Future<void> saveDeck(DrillDeck deck) async {
    await root.create(recursive: true);
    final tmp = File('${_drillFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(deck.toJson()));
    await tmp.rename(_drillFile.path);
  }
}
