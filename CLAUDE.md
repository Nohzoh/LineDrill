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
| Stockage | SQLite via `drift` |
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

## Règles de l'arbre

- Ne stocker que les 16 premiers demi-coups de chaque partie.
- Indexer les positions par FEN sans les compteurs de coups (4 premiers champs) pour fusionner les transpositions.
- Score du point de vue de l'utilisateur : 1 victoire, 0,5 nulle, 0 défaite.
- Ligne faible : coût = (0,5 − score) × nombre de parties, minimum 10 parties.

## Jalons

1. Import et arbre navigable avec scores, filtres couleur et cadence.
2. Lignes faibles classées + liens vers les parties.
3. Répertoire : coups de référence, explorateur Lichess, détection des déviations.
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

## Conventions

- Logique métier (import, parsing, arbre, planification) en Dart pur, testée avec `flutter test`, séparée de l'UI.
- Messages de commit en anglais.
