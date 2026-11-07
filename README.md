# LineDrill

Appli Android (Flutter) pour travailler ses ouvertures d'échecs à partir de ses propres parties Chess.com.

LineDrill importe tes parties, construit l'arbre de tes ouvertures avec ton score ligne par ligne, repère les lignes où tu perds des points, puis t'entraîne dessus en répétition espacée jusqu'à les jouer par réflexe.

## Fonctionnalités prévues (MVP)

1. **Import** des parties Chess.com par pseudo, mois par mois, stockées en local.
2. **Arbre et points faibles** : score par position, filtres couleur / cadence / période, classement des lignes les plus coûteuses.
3. **Répertoire** : un coup de référence par position, aide de l'explorateur Lichess (base maîtres), détection des déviations.
4. **Entraînement** : répétition espacée, mode apprentissage (sans chrono) et mode réflexe (chrono par coup).

## Stack

Flutter · `chessground` · `dartchess` · `multistockfish` (Stockfish 19) · `fsrs` · `http` · Riverpod · stockage local en fichiers.

## Statut

Jalons 1 à 3 en place : import Chess.com, arbre navigable avec filtres, lignes faibles, répertoire avec explorateur Lichess et détection des déviations. Jalon 4 : partie corrigée (répertoire puis Stockfish, correction coup par coup) et révisions en répétition espacée (FSRS), en mode apprentissage ou réflexe chronométré.

L'APK est compilé par GitHub Actions à chaque push sur `main` et publié dans les [releases](https://github.com/Nohzoh/LineDrill/releases/latest).

## Lancer

```sh
flutter pub get
flutter test
flutter run
```

## Licence

L'appli embarque [Stockfish](https://stockfishchess.org), sous licence GPLv3, via [multistockfish](https://github.com/lichess-org/dart-multistockfish). Distribuer l'APK implique de distribuer le code de LineDrill sous GPLv3.
