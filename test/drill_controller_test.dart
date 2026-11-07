import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/app/drill_controller.dart';
import 'package:linedrill/app/providers.dart';
import 'package:linedrill/core/drill.dart';

class _NoGames extends GamesNotifier {
  @override
  Future<GamesState> build() async => const GamesState(username: 'me');
}

void main() {
  late Directory tmp;
  late ProviderContainer container;
  var now = DateTime.utc(2026, 11, 7, 12);

  setUp(() async {
    now = DateTime.utc(2026, 11, 7, 12);
    tmp = await Directory.systemTemp.createTemp('linedrill');
    container = ProviderContainer(overrides: [
      appDirProvider.overrideWith((ref) async => tmp),
      gamesProvider.overrideWith(_NoGames.new),
      clockProvider.overrideWithValue(() => now),
    ]);
    await container.read(gamesProvider.future);
    await container.read(repertoireProvider.future);
    final rep = container.read(repertoireProvider.notifier);
    final e4 = Chess.initial.play(Move.parse('e2e4')!);
    await rep.setReference(Side.white, e4.play(Move.parse('g7g6')!), 'd4', const ['e4', 'g6']);
    await rep.setReference(Side.white, e4.play(Move.parse('c7c6')!), 'd4', const ['e4', 'c6']);
    await container.read(deckProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await tmp.delete(recursive: true);
  });

  DrillState s() => container.read(drillProvider);
  DrillController drill() => container.read(drillProvider.notifier);

  test('apprentissage : juste, faux puis rejouer le bon coup', () async {
    expect(container.read(dueProvider), hasLength(2));
    await drill().start(DrillMode.learning, Side.white);
    expect(s().cards, hasLength(2));
    expect(s().card!.position.turn, Side.white);
    expect(s().canPlay, isTrue);

    await drill().attempt(Move.parse('d2d4')!);
    expect(s().feedback, DrillFeedback.correct);
    expect(s().correct, 1);
    drill().next();

    await drill().attempt(Move.parse('g1f3')!);
    expect(s().feedback, DrillFeedback.wrong);
    expect(s().canPlay, isTrue);
    await drill().attempt(Move.parse('b1c3')!); // encore faux : pas de nouvelle note
    expect(s().wrong, 1);
    await drill().attempt(Move.parse('d2d4')!);
    expect(s().feedback, DrillFeedback.correct);
    expect(s().correct, 1);
    drill().next();
    expect(s().finished, isTrue);

    // Juste après : la ratée revient bientôt, la réussie plus tard.
    now = now.add(const Duration(minutes: 5));
    final due = container.read(dueProvider);
    expect(due.single.line, ['e4', 'c6']);
  });

  test('réflexe : chrono dépassé = raté, réponse rapide = facile', () async {
    await drill().start(DrillMode.reflex, Side.white);
    now = now.add(const Duration(seconds: 1));
    await drill().attempt(Move.parse('d2d4')!);
    expect(s().feedback, DrillFeedback.correct);
    drill().next();

    now = now.add(const Duration(seconds: 4));
    await drill().timeout();
    expect(s().feedback, DrillFeedback.timeout);
    expect(s().canPlay, isFalse);
    expect(s().wrong, 1);

    final deck = container.read(deckProvider).value!;
    final firstId = s().cards.first.entry.id;
    final secondId = s().cards.last.entry.id;
    expect(deck.cardFor(firstId, now).due.isAfter(deck.cardFor(secondId, now).due), isTrue);
  });

  test('le roque est reconnu quelle que soit sa notation', () async {
    Position p = Chess.initial;
    for (final uci in ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5']) {
      p = p.play(Move.parse(uci)!);
    }
    await container.read(repertoireProvider.notifier).setReference(
          Side.white, p, 'O-O', const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5']);
    await drill().start(DrillMode.learning, Side.white);
    while (s().card!.entry.san != 'O-O') {
      drill().next();
    }
    await drill().attempt(Move.parse('e1g1')!);
    expect(s().feedback, DrillFeedback.correct);
  });

  test('séance vide sans entrée due', () async {
    await drill().start(DrillMode.learning, Side.black);
    expect(s().finished, isTrue);
    expect(s().cards, isEmpty);
  });
}
