# LineDrill — contexte pour Claude Code

## Projet

Appli Android Flutter d'entraînement aux ouvertures d'échecs, basée sur les parties Chess.com de l'utilisateur.

- Package Android : `io.nohzoh.linedrill`
- Tout en local : pas de serveur, pas de compte.
- UI en français.

## Stack

| Couche             | Choix                                                                                                                                                                                                                                              |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Échiquier          | `chessground`                                                                                                                                                                                                                                      |
| Règles, PGN, FEN   | `dartchess`                                                                                                                                                                                                                                        |
| Stockage           | Fichiers dans le dossier privé de l'appli : PGN mensuels bruts, `repertoire.json`, `drill.json`, `habits.json`, `settings.json`, `lichess_token.txt`. Pas de SQLite tant que les volumes restent de quelques Ko (`drift` à reconsidérer si besoin) |
| Réseau             | `http`                                                                                                                                                                                                                                             |
| Répétition espacée | FSRS (paquet `fsrs`)                                                                                                                                                                                                                               |
| État               | Riverpod                                                                                                                                                                                                                                           |

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

## Moteur (partie corrigée)

- Stockfish 19 via `multistockfish` (Lichess), saveur `light` : réseau NNUE ~1 Mo embarqué, rien à télécharger. Android et iOS seulement.
- **Licence : Stockfish est sous GPLv3.** Distribuer l'APK oblige à distribuer le code de l'appli sous GPLv3.
- `lib/engine/chess_engine.dart` : interface `ChessEngine` + `UciEngine` (file d'analyses, MultiPV, mats convertis par `mateScore`). `stockfish_engine.dart` : branchement sur multistockfish.
- Roque : Stockfish parle `e1g1`, dartchess/chessground peuvent utiliser `e1h1` → toujours passer par `engineMove()` / `normalizeMove` et comparer les coups en SAN.
- Jugement d'un coup (`judgeMove`, `lib/core/training.dart`) : perte de chances de gain (courbe Lichess), seuils 0,1 imprécision, 0,2 erreur, 0,3 gaffe. Erreur et gaffe mettent la partie en pause (rejouer ou continuer).
- Explications (`lib/core/explain.dart`, `explainMove`) : à partir des lignes du moteur (`EngineLine.pv`), motifs reconnus — mat subi ou raté, bilan matériel au bout de la suite (échanges identiques annulés), pièce laissée en prise (« que tu viens de jouer » / « était attaquée »), fourchette, roque perdu — sinon évolution de l'évaluation. Une perte ou un gain de matériel n'est annoncé que si l'évaluation le confirme (sinon : échange coupé en plein milieu). UI : carte de correction (flèche rouge = réponse adverse, verte = meilleur coup) et « Pourquoi ? » sous le verdict pour les imprécisions.
- Partie (`lib/app/play_controller.dart`) : mes coups sont jugés contre mon répertoire tant qu'il couvre la position, puis par Stockfish ; l'adversaire joue les réponses de mes vraies parties tant que la position y figure, puis Stockfish à son niveau (`OpponentLevel` : profondeur + choix pondéré parmi les MultiPV).
- Tests avec un vrai Stockfish de bureau : `LINEDRILL_STOCKFISH=chemin/stockfish flutter test` (ignorés sinon). Pour le compiler depuis les sources du plugin : copier `multistockfish_light/ios/.../StockfishLight/src` et le `.nnue`, fournir `sfio::in()/out()` (std::cin/std::cout) et un `scripts/net.sh` vide, puis `make build ARCH=x86-64`.

## Règles de l'arbre

- Ne stocker que les 16 premiers demi-coups de chaque partie.
- Indexer les positions par FEN sans les compteurs de coups (4 premiers champs) pour fusionner les transpositions.
- Score du point de vue de l'utilisateur : 1 victoire, 0,5 nulle, 0 défaite.
- Ligne faible : coût = (score moyen de l'arbre filtré − score) × nombre de parties, minimum 10 parties. La référence est la moyenne et non 50 %, sinon 1.e4 (658 parties à 48 %) arrive en tête.
- Une suite quasi forcée est raccourcie (1.e4 g6 plutôt que 1.e4 g6 2.Nf3) ; une sous-ligne n'est gardée que si elle est au moins 5 points plus basse que sa ligne parente retenue (`lib/core/weak_lines.dart`).
- Rapport en console : `dart run tool/weak_lines_report.dart <pgn> <pseudo>`.

## Bilan des ouvertures

- Noms : `assets/openings.tsv` (position → nom), tiré de [lichess-org/chess-openings](https://github.com/lichess-org/chess-openings) (CC0) et limité aux 16 demi-coups de l'arbre. Noms en anglais ; la famille est ce qui précède les deux-points. Régénérer : `dart run tool/build_openings.dart <dossier des a.tsv … e.tsv> > assets/openings.tsv`.
- `openingReport` (`lib/core/opening_report.dart`) : depuis la position initiale, ouvre une variante par réponse adverse vue dans au moins N parties ; de mon côté un seul coup est suivi, l'étoile du répertoire si je la joue dans au moins N parties, sinon mon coup le plus joué (une étoile que je ne joue pas ne doit pas cacher ce que je joue). N = parties de la couleur ÷ 60, borné entre 5 et 10 : 10 comme les lignes faibles, moins après un premier import.
- Un coup est « connu » s'il est joué dans au moins 60 % des parties (au pour cent près, comme à l'affichage) et s'accorde avec le répertoire. La profondeur connue d'une variante compte les coups connus d'affilée depuis le début (8 au plus, l'arbre s'arrêtant à 16 demi-coups).
- Parties d'une variante = parties arrivées au bout de sa ligne, quel que soit l'ordre des coups. Deux ordres de coups qui se rejoignent ne font qu'une variante, celle du chemin le plus joué.
- Une partie compte dans une seule ouverture : celle de la position la plus profonde de son chemin que le parcours a traversée. Une ouverture compte donc aussi les parties qui quittent ses variantes en route (réponse adverse rare, autre coup de ma part).
- Rapport en console : `dart run tool/openings_report.dart <pgn> <pseudo>`.
- Vérification par Stockfish (bouton « Vérifier mes coups », `lib/app/habit_controller.dart`) : là où le répertoire ne dit rien, mes coups réguliers sont jugés par `judgeMove` à profondeur 12 (sans explication, `explain: false`), du plus joué au moins joué (trois au plus, chacun joué au moins une fois sur cinq, le plus joué toujours). Le coup à retenir est le premier qui n'est ni une erreur ni une gaffe, à défaut le meilleur coup du moteur ; une imprécision est gardée. Le moteur avance niveau par niveau : rien n'est demandé sous un coup qui attend encore son avis, et le contrôleur repasse tant que le bilan en demande. Un lancement garde la couleur et le filtre de son départ, et ce qu'il a jugé si le moteur tombe en route.
- Les avis sont gardés dans `habits.json` (clé : position + coup) avec la profondeur d'analyse (`judgeDepth`, la même qu'en partie corrigée) ; ils sont écrits tous les dix coups jugés. Ce n'est qu'un cache : un fichier illisible, ou rendu à une autre profondeur, est traité comme vide. Une analyse vide ou sans réponse au bout de 30 s arrête la vérification plutôt que d'être gardée comme « bon coup ».
- « Ajouter au répertoire » crée un coup de référence pour chaque position du bilan qui n'en a pas, sans jamais en remplacer un. Sous un coup à retenir que je ne joue pas assez pour être suivi, le bilan montre encore mes parties, mais ces positions sortent du répertoire : ni vérifiées ni ajoutées.
- Écran : Répertoire → « Mes ouvertures » (`lib/ui/openings_screen.dart`).

## Jalons

1. Import et arbre navigable avec scores, filtres couleur et cadence.
2. Lignes faibles classées + liens vers les parties.
3. Répertoire : coups de référence, explorateur Lichess, détection des déviations. Un coup de référence par position (FEN) et par couleur ; une partie compte comme « suivie » jusqu'à sa première déviation (`lib/core/repertoire.dart`).
4. Entraînement : partie corrigée (onglet Jouer) et révisions (onglet Répertoire).
   - Une carte FSRS (paquet `fsrs`) par coup de référence, stockée dans `drill.json` (`lib/core/drill.dart`). File du jour : en retard d'abord, puis nouvelles, les coups les plus souvent manqués dans mes parties en tête ; 20 par séance.
   - Apprentissage : pas de chrono, après une erreur il faut jouer le bon coup (sans nouvelle note). Réflexe : 3 s par coup ; dépassé = raté, moins de 1,5 s = « facile ».
   - Séance : `lib/app/drill_controller.dart`, écran `lib/ui/drill_screen.dart`.
5. Préparation automatique du répertoire (`lib/core/repertoire_builder.dart`, `lib/app/builder_controller.dart`, `lib/ui/builder_screen.dart`, bouton dans l'onglet Répertoire) : parcours en largeur de l'arbre filtré ; dans chaque position atteinte ≥ 3 fois où c'est à moi de jouer, mon coup le plus joué est jugé par `judgeMove` → gardé (bon), « à vérifier » (imprécision, ou erreur qui laisse encore ≥ +2), « corrigé » (erreur/gaffe → meilleur coup). Réponses adverses suivies si ≥ 3 parties ; profondeur max 14 demi-coups ; une ligne corrigée par un coup jamais joué s'arrête. Rien n'est enregistré sans validation ; les propositions qui diffèrent d'un coup de référence existant sont décochées par défaut. Rapport console : `dart run tool/build_repertoire_report.dart <pgn> <pseudo> <stockfish> [white|black]` (~30 s par couleur sur octobre).

## Données de référence (octobre 2026, pseudo Lappeau)

Pour valider les jalons 1 et 2 : 1 322 parties, toutes en bullet 1+0, score global 50,6 % (Blancs 48,5 %, Noirs 52,6 %).
Lignes faibles attendues :

| Couleur | Ligne                                 | Parties | Score |
| ------- | ------------------------------------- | ------- | ----- |
| Blancs  | 1.e4 g6                               | 26      | 25 %  |
| Blancs  | 1.e4 d5 2.exd5 Qxd5 3.Nc3 Qe6+ / Qe5+ | 25      | 32 %  |
| Blancs  | 1.e4 d5 2.exd5 Qxd5 3.Nc3 Qd8         | 35      | 40 %  |
| Blancs  | 1.e4 c6                               | 50      | 41 %  |
| Blancs  | 1.e4 e5 2.Nf3 Nc6 3.d4 Nf6            | 37      | 45 %  |
| Noirs   | 1.e4 d5 2.exd5 Qxd5 3.Nc3 Qa5 4.d4 c6 | 27      | 35 %  |
| Noirs   | 1.d4 d5 2.e3                          | 21      | 38 %  |

## Code

- `lib/core/` : modèle et logique pure (`game_record`, `pgn_import`, `opening_tree`, `weak_lines`, `repertoire`, `openings`, `opening_report`).
- `lib/data/` : client Chess.com, stockage des PGN, service d'import, client explorateur Lichess, stockage du répertoire et du jeton.
- `lib/app/providers.dart` : providers Riverpod. `lib/app/habit_controller.dart` : vérification de mes coups habituels par Stockfish. `lib/app/board_style.dart` : apparence de l'échiquier (par défaut vert + pièces Staunty, proche de Chess.com ; jeux de pièces libres de chessground uniquement, ne pas copier les pièces propriétaires de Chess.com), stockée dans `settings.json` (clé `board`). Couleur et niveau de la partie corrigée : `playSetupProvider`, clé `play`.
- `lib/ui/` : `home_shell` (filtres + onglets Arbre / Points faibles / Répertoire / Jouer), `play_view` (partie corrigée), `builder_screen` (préparation automatique), `explanation_view` (explications partagées), `tree_view` (étoile = coup de référence), `weak_lines_view`, `repertoire_view`, `openings_screen` (bilan des ouvertures), `explorer_sheet`, `games_sheet` (parties d'une ligne, liens Chess.com), `import_screen`, `settings_screen`.
- Tests widget : la table des noms d'ouvertures est remplacée par une table réduite (`openingBookProvider`). Le dossier de l'appli est remplacé par un dossier temporaire (`appDirProvider`) ; laisser finir les entrées-sorties avec `tester.runAsync` avant `pumpAndSettle`. Ne pas attendre une méthode de notifier qui fait `await future` à l'intérieur de `runAsync` (blocage) : la lancer avec `unawaited` puis faire avancer les zones. Pour un provider au type nullable, ne pas écrire `return container.read(provider)!` : le type attendu perd son `?` et Riverpod lève une `NoSuchMethodError` (`_listenedElement`) ; lire dans une variable, puis `!`.
- Test sur données réelles : `LINEDRILL_REF_PGN=chemin/du/pgn flutter test` (ignoré sinon). L'arbre fusionne les transpositions, donc certains comptes dépassent ceux du tableau ci-dessus (ex. Noirs 4.d4 c6 : 30 parties, 42 %).

## Conventions

- Logique métier (import, parsing, arbre, planification) en Dart pur, testée avec `flutter test`, séparée de l'UI.
- Messages de commit en anglais.
- CI : Flutter figé sur 3.47.9 dans `.github/workflows/build-apk.yml` (même version qu’en local). Flutter 3.50 déclare `package:flutter/material.dart` obsolète au profit de `package:material_ui` : Material est déjà importé depuis `material_ui` partout (analyse et tests passent en 3.47.9 comme en 3.50.0), il ne reste qu'à monter la version.
