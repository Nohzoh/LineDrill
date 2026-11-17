import 'dart:convert';
import 'dart:io';

import '../core/drill.dart';
import '../core/opening_report.dart';
import '../core/repertoire.dart';

/// Répertoire et réglages, stockés en JSON dans le dossier de l'appli.
class RepertoireStore {
  RepertoireStore(this.root);

  final Directory root;

  File get _repertoireFile => File('${root.path}/repertoire.json');

  File get _tokenFile => File('${root.path}/lichess_token.txt');

  File get _settingsFile => File('${root.path}/settings.json');

  File get _drillFile => File('${root.path}/drill.json');

  File get _habitsFile => File('${root.path}/habits.json');

  // Lectures synchrones : ces fichiers ne font que quelques Ko.
  Future<Repertoire> loadRepertoire() async {
    if (!_repertoireFile.existsSync()) return Repertoire();
    return Repertoire.fromJson(jsonDecode(_repertoireFile.readAsStringSync()) as List<Object?>);
  }

  /// Écrit dans un fichier temporaire puis le renomme, pour ne jamais
  /// laisser un fichier à moitié écrit.
  Future<void> _writeAtomic(File file, String content) async {
    await root.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content);
    await tmp.rename(file.path);
  }

  Future<void> saveRepertoire(Repertoire repertoire) =>
      _writeAtomic(_repertoireFile, const JsonEncoder.withIndent(' ').convert(repertoire.toJson()));

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
    final write = _settingsQueue.then(
      (_) => _writeAtomic(_settingsFile, jsonEncode({..._readSettings(), key: value})),
    );
    _settingsQueue = write.catchError((Object _) {});
    return write;
  }

  /// Avis de Stockfish sur mes coups habituels, par `habitCheckKey`, rendus
  /// à la profondeur d'analyse [depth].
  ///
  /// Ce n'est qu'un cache : un fichier illisible, ou écrit à une autre
  /// profondeur, est traité comme vide et les coups sont jugés à nouveau.
  Future<Map<String, HabitCheck>> loadHabitChecks({required int depth}) async {
    if (!_habitsFile.existsSync()) return {};
    try {
      final json = (jsonDecode(_habitsFile.readAsStringSync()) as Map).cast<String, Object?>();
      if (json['depth'] != depth) return {};
      final checks = (json['checks']! as Map).cast<String, Object?>();
      return {
        for (final e in checks.entries)
          if (e.value is Map) e.key: ?HabitCheck.fromJson((e.value! as Map).cast<String, Object?>()),
      };
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }

  Future<void> saveHabitChecks(Map<String, HabitCheck> checks, {required int depth}) => _writeAtomic(
        _habitsFile,
        jsonEncode({
          'depth': depth,
          'checks': {for (final e in checks.entries) e.key: e.value.toJson()},
        }),
      );

  /// État des révisions (répétition espacée).
  Future<DrillDeck> loadDeck() async {
    if (!_drillFile.existsSync()) return DrillDeck();
    return DrillDeck.fromJson((jsonDecode(_drillFile.readAsStringSync()) as Map).cast<String, Object?>());
  }

  Future<void> saveDeck(DrillDeck deck) => _writeAtomic(_drillFile, jsonEncode(deck.toJson()));
}
