# LineDrill — contexte pour Claude Code

## Projet

Appli Android Flutter d'entraînement aux ouvertures d'échecs, basée sur les parties Chess.com de l'utilisateur.
- Package Android : `io.nohzoh.linedrill`
- Tout en local : pas de serveur, pas de compte.
- UI en français.

## Stack

| Couche | Choix |
| --- | --- |
| Échiquier | `chessground` |
| Règles, PGN, FEN | `dartchess` |
| Stockage | Fichiers dans le dossier privé de l'appli : PGN mensuels bruts, `repertoire.json`, `lichess_token.txt`. Pas de SQLite tant que les volumes restent de quelques Ko (`drift` à reconsidérer si besoin) |
| Réseau | `http` |
| Répétition espacée | FSRS (SM-2 en repli) |
| État | Riverpod |

## Données Chess.com

- API publique, sans authentification. Envoyer un User-Agent identifiant l'appli (`LineDrill`), sans email.
- Liste des mois : `GET https://api.chess.com/pub/player/{pseudo}/games/archives`
- Parties d'un mois en PGN : `GET https://api.chess.com/pub/player/{pseudo}/games/{AAAA}/{MM}/pgn`
- Tags utiles : `White`, `Black`, `Result`, `TimeControl` (`60`, `180+2`…), `WhiteElo`, `BlackElo`, `Termination`, `ECOUrl`, `Link`, `UTCDate`.
- Ignorer les variantes non standard (tag `Variant`).
- Cadence : temps estimé = base + 40 × incrément ; < 180 s bullet, < 600 s blitz, sinon rapide.

## Explorateur Lichess

- `https://explorer.lichess.ovh/masters` (maîtres) et `/lichess` (bullet + blitz, tranches 1000 à 1600, soit 1000–1799 Elo).
- Exige un jeton personnel (`Authorization: Bearer`), créé sans permission sur https://lichess.org/account/oauth/token/create ; saisi dans Réglages.

## Règles de l'arbre

- Ne stocker que les 16 premiers demi-coups de chaque partie.
- Indexer les positions par FEN sans les compteurs de coups (4 premiers champs) pour fusionner les transpositions.
- Score du point de vue de l'utilisateur : 1 victoire, 0,5 nulle, 0 défaite.
- Ligne faible : coût = (score moyen de l'arbre filtré − score) × nombre de parties, minimum 10 parties. La référence est la moyenne et non 50 %, sinon 1.e4 (658 parties à 48 %) arrive en tête.
- Une suite quasi forcée est raccourcie (1.e4 g6 plutôt que 1.e4 g6 2.Nf3) ; une sous-ligne n'est gardée que si elle est au moins 5 points plus basse que sa ligne parente retenue (`lib/core/weak_lines.dart`).
- Rapport en console : `dart run tool/weak_lines_report.dart <pgn> <pseudo>`.

## Jalons

1. Import et arbre navigable avec scores, filtres couleur et cadence.
2. Lignes faibles classées + liens vers les parties.
3. Répertoire : coups de référence, explorateur Lichess, détection des déviations. Un coup de référence par position (FEN) et par couleur ; une partie compte comme « suivie » jusqu'à sa première déviation (`lib/core/repertoire.dart`).
4. Entraînement : répétition espacée, modes apprentissage et réflexe.

## Données de référence (octobre 2026, pseudo Lappeau)

Pour valider les jalons 1 et 2 : 1 322 parties, toutes en bullet 1+0, score global 50,6 % (Blancs 48,5 %, Noirs 52,6 %).
Lignes faibles attendues :

| Couleur | Ligne | Parties | Score |
| --- | --- | --- | --- |
| Blancs | 1.e4 g6 | 26 | 25 % |
| Blancs | 1.e4 d5 2.exd5 Qxd5 3.Nc3 Qe6+ / Qe5+ | 25 | 32 % |
| Blancs | 1.e4 d5 2.exd5 Qxd5 3.Nc3 Qd8 | 35 | 40 % |
| Blancs | 1.e4 c6 | 50 | 41 % |
| Blancs | 1.e4 e5 2.Nf3 Nc6 3.d4 Nf6 | 37 | 45 % |
| Noirs | 1.e4 d5 2.exd5 Qxd5 3.Nc3 Qa5 4.d4 c6 | 27 | 35 % |
| Noirs | 1.d4 d5 2.e3 | 21 | 38 % |

## Code

- `lib/core/` : modèle et logique pure (`game_record`, `pgn_import`, `opening_tree`, `weak_lines`, `repertoire`).
- `lib/data/` : client Chess.com, stockage des PGN, service d'import, client explorateur Lichess, stockage du répertoire et du jeton.
- `lib/app/providers.dart` : providers Riverpod.
- `lib/ui/` : `home_shell` (filtres + onglets Arbre / Points faibles / Répertoire), `tree_view` (étoile = coup de référence), `weak_lines_view`, `repertoire_view`, `explorer_sheet`, `games_sheet` (parties d'une ligne, liens Chess.com), `import_screen`, `settings_screen`.
- Tests widget : le dossier de l'appli est remplacé par un dossier temporaire (`appDirProvider`) ; laisser finir les entrées-sorties avec `tester.runAsync` avant `pumpAndSettle`.
- Test sur données réelles : `LINEDRILL_REF_PGN=chemin/du/pgn flutter test` (ignoré sinon). L'arbre fusionne les transpositions, donc certains comptes dépassent ceux du tableau ci-dessus (ex. Noirs 4.d4 c6 : 30 parties, 42 %).

## Conventions

- Logique métier (import, parsing, arbre, planification) en Dart pur, testée avec `flutter test`, séparée de l'UI.
- Messages de commit en anglais.
