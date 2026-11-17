/// Nom d'une ouverture, tel que Lichess le donne :
/// « Scandinavian Defense: Mieses-Kotrč Variation ».
class OpeningName {
  const OpeningName(this.full);

  final String full;

  /// Famille : ce qui précède les deux-points (« Scandinavian Defense »).
  String get family => full.split(':').first.trim();

  /// Variante : ce qui suit les deux-points, ou `null` pour la ligne mère.
  String? get variation {
    final colon = full.indexOf(':');
    return colon < 0 ? null : full.substring(colon + 1).trim();
  }
}

/// Noms des ouvertures par position (clé `positionKey`), pour nommer les
/// lignes de l'arbre quel que soit l'ordre des coups.
class OpeningBook {
  const OpeningBook(this._names);

  /// Lit `assets/openings.tsv` : une ligne `clé<TAB>nom` par position.
  factory OpeningBook.parse(String tsv) {
    final names = <String, String>{};
    for (final row in tsv.split('\n')) {
      final tab = row.indexOf('\t');
      if (tab > 0) names[row.substring(0, tab)] = row.substring(tab + 1).trim();
    }
    return OpeningBook(names);
  }

  static const empty = OpeningBook({});

  final Map<String, String> _names;

  int get length => _names.length;

  OpeningName? nameOf(String positionKey) {
    final name = _names[positionKey];
    return name == null ? null : OpeningName(name);
  }
}
