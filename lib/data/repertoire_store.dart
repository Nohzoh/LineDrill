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

  /// Préférences d'affichage, en JSON libre.
  Future<Map<String, Object?>> settings() async {
    if (!_settingsFile.existsSync()) return {};
    return (jsonDecode(_settingsFile.readAsStringSync()) as Map).cast<String, Object?>();
  }

  Future<void> saveSettings(Map<String, Object?> settings) async {
    await root.create(recursive: true);
    await _settingsFile.writeAsString(jsonEncode(settings));
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
