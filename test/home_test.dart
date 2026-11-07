import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:dartchess/dartchess.dart' hide File;
import 'package:linedrill/app/drill_controller.dart';
import 'package:linedrill/app/play_controller.dart';
import 'package:linedrill/app/providers.dart';
import 'package:linedrill/engine/chess_engine.dart';
import 'package:linedrill/core/pgn_import.dart';
import 'package:linedrill/ui/games_sheet.dart';
import 'package:linedrill/ui/home_shell.dart';

const _pgn = '''
[White "Lappeau"]
[Black "a"]
[Result "1-0"]
[TimeControl "60"]

1. e4 e5 2. Nf3 Nc6 1-0

[White "Lappeau"]
[Black "b"]
[Result "0-1"]
[TimeControl "60"]

1. e4 c6 2. Nf3 d5 0-1

[White "Lappeau"]
[Black "c"]
[Result "1-0"]
[TimeControl "180"]

1. e4 e5 2. Nf3 d6 1-0

[White "d"]
[Black "Lappeau"]
[Result "1-0"]
[TimeControl "60"]

1. d4 d5 1-0
''';

class _FakeGames extends GamesNotifier {
  @override
  Future<GamesState> build() async =>
      GamesState(username: 'Lappeau', games: parseGames(_pgn, 'Lappeau'));
}

void main() {
  weakLinesTests();
  repertoireTests();
  playTests();
  drillTests();

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [gamesProvider.overrideWith(_FakeGames.new), _tmpDir()],
      child: const MaterialApp(home: HomeShell()),
    ));
    await _settle(tester);
  }

  testWidgets('affiche les coups et navigue dans l\'arbre', (tester) async {
    await pump(tester);
    expect(find.textContaining('Lappeau · 3 parties · score 67 %'), findsOneWidget);
    expect(find.text('1. e4'), findsOneWidget);

    await tester.tap(find.text('1. e4'));
    await _settle(tester);
    expect(find.text('1… e5'), findsOneWidget);
    expect(find.text('1… c6'), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);
    expect(find.text('0 %'), findsOneWidget);
  });

  testWidgets('filtres couleur et cadence', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Noirs'));
    await _settle(tester);
    expect(find.text('1. d4'), findsOneWidget);
    expect(find.text('1. e4'), findsNothing);

    await tester.tap(find.text('Blancs'));
    await tester.tap(find.text('Blitz'));
    await _settle(tester);
    expect(find.textContaining('1 parties'), findsWidgets);
  });
}

String _many(int n, String moves, String result) => List.generate(
      n,
      (i) => '[White "Lappeau"]\n[Black "opp$i"]\n[Result "$result"]\n[TimeControl "60"]\n'
          '[UTCDate "2026.10.${(i % 28 + 1).toString().padLeft(2, '0')}"]\n'
          '[Termination "opp$i won on time"]\n[Link "https://www.chess.com/game/live/$i"]\n\n'
          '$moves $result\n',
    ).join('\n');

class _WeakGames extends GamesNotifier {
  @override
  Future<GamesState> build() async => GamesState(
        username: 'Lappeau',
        games: parseGames(
          '${_many(12, '1. e4 c5 2. Nf3', '0-1')}\n${_many(12, '1. e4 e5 2. Nf3', '1-0')}',
          'Lappeau',
        ),
      );
}

void weakLinesTests() {
  testWidgets('points faibles : classement, arbre et parties', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [gamesProvider.overrideWith(_WeakGames.new), _tmpDir()],
      child: const MaterialApp(home: HomeShell()),
    ));
    await _settle(tester);

    await tester.tap(find.text('Points faibles'));
    await _settle(tester);
    expect(find.text('#1  1. e4 c5', findRichText: true), findsOneWidget);
    expect(find.text('Réponse adverse : que jouer ici ?'), findsOneWidget);

    await tester.tap(find.text('Parties').first);
    await _settle(tester);
    expect(find.text('12 parties · 0 victoires, 0 nulles, 12 défaites'), findsOneWidget);
    expect(find.textContaining('Défaite au temps'), findsWidgets);
    Navigator.of(tester.element(find.byType(GamesList))).pop();
    await _settle(tester);

    await tester.tap(find.text('#1  1. e4 c5', findRichText: true));
    await _settle(tester);
    expect(find.text('2. Nf3'), findsOneWidget);
    expect(find.textContaining('Cette ligne : 12 parties · 0 %'), findsOneWidget);
  });
}

/// Dossier temporaire à la place du dossier de l'appli (pas de path_provider en test).
Override _tmpDir() {
  final dir = Directory.systemTemp.createTempSync('linedrill');
  addTearDown(() => dir.deleteSync(recursive: true));
  return appDirProvider.overrideWith((ref) async => dir);
}

void repertoireTests() {
  testWidgets('répertoire : étoile dans l\'arbre, onglet Répertoire', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [gamesProvider.overrideWith(_WeakGames.new), _tmpDir()],
      child: const MaterialApp(home: HomeShell()),
    ));
    await _settle(tester);

    await tester.tap(find.text('1. e4'));
    await _settle(tester);
    await tester.tap(find.text('1… c5'));
    await _settle(tester);
    expect(find.text('Pas encore de coup de référence ici'), findsOneWidget);

    await tester.tap(find.byTooltip('Choisir comme coup de référence'));
    await _settle(tester);
    expect(find.text('Mon coup : 2. Nf3'), findsOneWidget);
    expect(find.textContaining('Joué dans 12 parties (0 %)'), findsOneWidget);

    await tester.tap(find.text('Répertoire'));
    await _settle(tester);
    expect(find.text('Joué 12 fois sur 12 (0 %)'), findsOneWidget);
    expect(find.textContaining('1 coups de référence'), findsOneWidget);

    await tester.tap(find.byTooltip('Retirer'));
    await _settle(tester);
    expect(find.textContaining('Aucun coup de référence'), findsOneWidget);
  });
}

/// Laisse finir les entrées-sorties réelles (fichiers) puis les animations.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

/// Moteur factice : toute position après un coup blanc est perdante pour les Blancs.
class _HarshEngine implements ChessEngine {
  @override
  Future<List<EngineLine>> analyse(String fen, {int depth = 12, int multiPv = 1}) async {
    final p = Chess.fromSetup(Setup.parseFen(fen));
    final first = p.legalMoves.entries.firstWhere((e) => e.value.isNotEmpty);
    final uci = NormalMove(from: first.key, to: first.value.squares.first).uci;
    return [EngineLine(uci, p.turn == Side.black ? 800 : 30)];
  }

  @override
  Future<void> dispose() async {}
}

void playTests() {
  testWidgets('jouer : correction et rejouer', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        gamesProvider.overrideWith(_WeakGames.new),
        _tmpDir(),
        engineProvider.overrideWith((ref) async => _HarshEngine()),
      ],
      child: const MaterialApp(home: HomeShell()),
    ));
    await _settle(tester);

    await tester.tap(find.text('Jouer'));
    await _settle(tester);
    await tester.tap(find.text('Commencer'));
    await _settle(tester);
    expect(find.text('À toi de jouer'), findsOneWidget);
    expect(find.text('Stockfish'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    await tester.runAsync(() => container.read(playProvider.notifier).play(Move.parse('e2e4')!));
    await _settle(tester);
    expect(find.textContaining('Gaffe : 1. e4'), findsOneWidget);
    expect(find.textContaining('Mieux : 1.'), findsOneWidget);

    await tester.tap(find.text('Rejouer'));
    await _settle(tester);
    expect(find.textContaining('Gaffe'), findsNothing);
    expect(find.text('À toi de jouer'), findsOneWidget);

    await tester.tap(find.byTooltip('Nouvelle partie'));
    await _settle(tester);
    expect(find.text('Commencer'), findsOneWidget);
  });
}

void drillTests() {
  Future<ProviderContainer> setUpDrill(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [gamesProvider.overrideWith(_WeakGames.new), _tmpDir()],
      child: const MaterialApp(home: HomeShell()),
    ));
    await _settle(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final e4 = Chess.initial.play(Move.parse('e2e4')!);
    final rep = container.read(repertoireProvider.notifier);
    // Pas de runAsync ici : attendre le futur d'un provider depuis la zone
    // réelle bloquerait ; _settle fait avancer les deux zones.
    unawaited(rep.setReference(Side.white, e4.play(Move.parse('c7c5')!), 'Nf3', const ['e4', 'c5']));
    await _settle(tester);
    unawaited(rep.setReference(Side.white, e4.play(Move.parse('e7e5')!), 'Nf3', const ['e4', 'e5']));
    await _settle(tester);
    await tester.tap(find.text('Répertoire'));
    await _settle(tester);
    return container;
  }

  testWidgets('révision : apprentissage jusqu\'au bilan', (tester) async {
    final container = await setUpDrill(tester);
    expect(find.text('2 lignes à réviser'), findsOneWidget);

    await tester.tap(find.text('Réviser'));
    await _settle(tester);
    expect(find.text('Révision · Apprentissage'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    final drill = container.read(drillProvider.notifier);
    unawaited(drill.attempt(Move.parse('g1f3')!));
    await tester.pump();
    expect(find.textContaining('Juste : 2. Nf3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(find.text('2 / 2'), findsOneWidget);

    unawaited(drill.attempt(Move.parse('d2d4')!));
    await _settle(tester);
    expect(find.textContaining('Joue-le pour continuer'), findsOneWidget);
    unawaited(drill.attempt(Move.parse('g1f3')!));
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(find.text('Séance terminée'), findsOneWidget);
    expect(find.textContaining('1 justes sur 2'), findsOneWidget);

    await tester.tap(find.text('Terminer'));
    await _settle(tester);
    expect(find.textContaining('lignes à réviser'), findsNothing);
    expect(find.textContaining('Prochaine révision'), findsOneWidget);
  });

  testWidgets('révision : réflexe, le chrono expire', (tester) async {
    await setUpDrill(tester);
    await tester.tap(find.text('Réflexe (3 s)'));
    await _settle(tester);
    expect(find.text('Révision · Réflexe'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await _settle(tester);
    expect(find.textContaining('Temps écoulé'), findsOneWidget);
    await tester.tap(find.text('Suivant'));
    await _settle(tester);
    expect(find.text('2 / 2'), findsOneWidget);
  });
}
