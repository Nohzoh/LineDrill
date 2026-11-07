import 'package:dartchess/dartchess.dart';

import 'game_record.dart';
import 'opening_tree.dart';

/// Coup de référence de l'utilisateur dans une position où c'est à lui de jouer.
class RepertoireEntry {
  const RepertoireEntry({
    required this.color,
    required this.positionKey,
    required this.san,
    required this.line,
  });

  /// Couleur jouée par l'utilisateur.
  final Side color;

  /// Position, au format de [positionKey] (FEN sans compteurs).
  final String positionKey;

  /// Coup de référence, en SAN.
  final String san;

  /// Ligne par laquelle la position a été atteinte quand l'entrée a été
  /// créée, pour l'affichage (la position peut être atteinte autrement).
  final List<String> line;

  String get id => Repertoire.idOf(color, positionKey);

  Map<String, Object?> toJson() => {
        'color': color.name,
        'position': positionKey,
        'san': san,
        'line': line,
      };

  factory RepertoireEntry.fromJson(Map<String, Object?> json) => RepertoireEntry(
        color: Side.values.byName(json['color']! as String),
        positionKey: json['position']! as String,
        san: json['san']! as String,
        line: (json['line']! as List).cast<String>(),
      );
}

/// Ensemble des coups de référence, un au plus par position et par couleur.
class Repertoire {
  Repertoire([Iterable<RepertoireEntry> entries = const []])
      : _entries = {for (final e in entries) e.id: e};

  final Map<String, RepertoireEntry> _entries;

  static String idOf(Side color, String positionKey) => '${color.name}|$positionKey';

  Iterable<RepertoireEntry> get entries => _entries.values;

  RepertoireEntry? lookup(Side color, String positionKey) => _entries[idOf(color, positionKey)];

  /// Copie avec [entry] ajoutée ou remplacée.
  Repertoire withEntry(RepertoireEntry entry) => Repertoire([..._entries.values.where((e) => e.id != entry.id), entry]);

  /// Copie sans l'entrée de cette position.
  Repertoire without(Side color, String positionKey) {
    final id = idOf(color, positionKey);
    return Repertoire(_entries.values.where((e) => e.id != id));
  }

  List<Map<String, Object?>> toJson() => [for (final e in _entries.values) e.toJson()];

  factory Repertoire.fromJson(List<Object?> json) =>
      Repertoire(json.map((e) => RepertoireEntry.fromJson((e! as Map).cast<String, Object?>())));
}

/// Une partie où l'utilisateur n'a pas joué son coup de référence.
class Deviation {
  const Deviation(this.game, this.played);

  final GameRecord game;

  /// Coup joué à la place, en SAN.
  final String played;
}

/// Comment une entrée du répertoire est respectée dans les vraies parties.
class EntryUsage {
  EntryUsage(this.entry);

  final RepertoireEntry entry;

  /// Parties qui ont atteint la position et où le coup de référence a été joué.
  final List<GameRecord> followed = [];

  /// Parties qui ont atteint la position et où un autre coup a été joué.
  final List<Deviation> deviated = [];

  int get reached => followed.length + deviated.length;

  double? get followedScore => _score(followed);

  double? get deviatedScore => _score([for (final d in deviated) d.game]);

  static double? _score(List<GameRecord> games) =>
      games.isEmpty ? null : games.fold<double>(0, (s, g) => s + g.score) / games.length;
}

/// Mesure, pour chaque entrée de [repertoire], combien de parties la
/// respectent ou s'en écartent. Une partie s'arrête à sa première déviation :
/// la suite n'est plus « dans le répertoire ».
Map<String, EntryUsage> repertoireUsage(Iterable<GameRecord> games, Repertoire repertoire) {
  final usage = {for (final e in repertoire.entries) e.id: EntryUsage(e)};
  if (usage.isEmpty) return usage;
  for (final game in games) {
    Position position = Chess.initial;
    for (final san in game.sans) {
      if (position.turn == game.color) {
        final entry = repertoire.lookup(game.color, positionKey(position));
        if (entry != null) {
          if (san == entry.san) {
            usage[entry.id]!.followed.add(game);
          } else {
            usage[entry.id]!.deviated.add(Deviation(game, san));
            break;
          }
        }
      }
      final move = position.parseSan(san);
      if (move == null) break;
      position = position.play(move);
    }
  }
  return usage;
}
