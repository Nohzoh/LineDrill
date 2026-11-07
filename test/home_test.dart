import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/app/providers.dart';
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

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [gamesProvider.overrideWith(_FakeGames.new)],
      child: const MaterialApp(home: HomeShell()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('affiche les coups et navigue dans l\'arbre', (tester) async {
    await pump(tester);
    expect(find.textContaining('Lappeau · 3 parties · score 67 %'), findsOneWidget);
    expect(find.text('1. e4'), findsOneWidget);

    await tester.tap(find.text('1. e4'));
    await tester.pumpAndSettle();
    expect(find.text('1… e5'), findsOneWidget);
    expect(find.text('1… c6'), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);
    expect(find.text('0 %'), findsOneWidget);
  });

  testWidgets('filtres couleur et cadence', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Noirs'));
    await tester.pumpAndSettle();
    expect(find.text('1. d4'), findsOneWidget);
    expect(find.text('1. e4'), findsNothing);

    await tester.tap(find.text('Blancs'));
    await tester.tap(find.text('Blitz'));
    await tester.pumpAndSettle();
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
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [gamesProvider.overrideWith(_WeakGames.new)],
      child: const MaterialApp(home: HomeShell()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Points faibles'));
    await tester.pumpAndSettle();
    expect(find.text('#1  1. e4 c5', findRichText: true), findsOneWidget);
    expect(find.text('Réponse adverse : que jouer ici ?'), findsOneWidget);

    await tester.tap(find.text('Parties').first);
    await tester.pumpAndSettle();
    expect(find.text('12 parties · 0 victoires, 0 nulles, 12 défaites'), findsOneWidget);
    expect(find.textContaining('Défaite au temps'), findsWidgets);
    Navigator.of(tester.element(find.byType(GamesList))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('#1  1. e4 c5', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('2. Nf3'), findsOneWidget);
    expect(find.textContaining('Cette ligne : 12 parties · 0 %'), findsOneWidget);
  });
}
