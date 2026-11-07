# LineDrill

Appli Android (Flutter) pour travailler ses ouvertures d'échecs à partir de ses propres parties Chess.com.

LineDrill importe tes parties, construit l'arbre de tes ouvertures avec ton score ligne par ligne, repère les lignes où tu perds des points, puis t'entraîne dessus en répétition espacée jusqu'à les jouer par réflexe.

## Fonctionnalités prévues (MVP)

1. **Import** des parties Chess.com par pseudo, mois par mois, stockées en local.
2. **Arbre et points faibles** : score par position, filtres couleur / cadence / période, classement des lignes les plus coûteuses.
3. **Répertoire** : un coup de référence par position, aide de l'explorateur Lichess (base maîtres), détection des déviations.
4. **Entraînement** : répétition espacée, mode apprentissage (sans chrono) et mode réflexe (chrono par coup).

## Stack

Flutter · `chessground` · `dartchess` · SQLite via `drift` · `http` · Riverpod · FSRS.

## Statut

Jalon 1 (import Chess.com + arbre navigable avec filtres) en place. Prochain : jalon 2, classement des lignes faibles.

## Lancer

```sh
flutter pub get
flutter test
flutter run
```
