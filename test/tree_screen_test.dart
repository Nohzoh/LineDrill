import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/app/providers.dart';
import 'package:linedrill/core/pgn_import.dart';
import 'package:linedrill/ui/tree_screen.dart';

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
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [gamesProvider.overrideWith(_FakeGames.new)],
      child: const MaterialApp(home: TreeScreen()),
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
