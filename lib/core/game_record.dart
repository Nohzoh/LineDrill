import 'package:dartchess/dartchess.dart';

/// Cadence d'une partie, dérivée du tag PGN `TimeControl`.
enum TimeClass {
  bullet('Bullet'),
  blitz('Blitz'),
  rapid('Rapide'),
  other('Autre');

  const TimeClass(this.label);

  final String label;

  /// Temps estimé = base + 40 × incrément ;
  /// < 180 s bullet, < 600 s blitz, sinon rapide.
  static TimeClass fromTimeControl(String? timeControl) {
    if (timeControl == null) return TimeClass.other;
    final parts = timeControl.split('+');
    final base = int.tryParse(parts[0]);
    if (base == null) return TimeClass.other;
    final increment = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final estimated = base + 40 * increment;
    if (estimated < 180) return TimeClass.bullet;
    if (estimated < 600) return TimeClass.blitz;
    return TimeClass.rapid;
  }
}

/// Une partie importée, réduite à ce dont l'arbre d'ouvertures a besoin.
class GameRecord {
  const GameRecord({
    required this.color,
    required this.score,
    required this.timeClass,
    required this.sans,
    this.link,
    this.date,
    this.elo,
  });

  /// Couleur jouée par l'utilisateur.
  final Side color;

  /// Score du point de vue de l'utilisateur : 1, 0,5 ou 0.
  final double score;

  final TimeClass timeClass;

  /// Premiers demi-coups de la partie en SAN (16 au maximum), tous légaux.
  final List<String> sans;

  /// Lien vers la partie sur Chess.com.
  final String? link;

  /// Date UTC au format `AAAA.MM.JJ`.
  final String? date;

  /// Elo de l'utilisateur dans cette partie.
  final int? elo;
}
