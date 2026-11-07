import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/game_record.dart';
import 'format.dart';

/// Ouvre la liste des parties d'une ligne dans une feuille du bas.
Future<void> showGamesSheet(BuildContext context, String title, List<GameRecord> games) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) => GamesList(
        title: title,
        games: games,
        controller: controller,
      ),
    ),
  );
}

/// Parties d'une ligne, les plus récentes d'abord, avec lien vers Chess.com.
class GamesList extends StatelessWidget {
  const GamesList({super.key, required this.title, required this.games, this.controller});

  final String title;
  final List<GameRecord> games;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final sorted = [...games]..sort((a, b) => (b.date ?? '').compareTo(a.date ?? ''));
    final wins = games.where((g) => g.score == 1).length;
    final draws = games.where((g) => g.score == 0.5).length;
    final losses = games.length - wins - draws;
    return ListView(
      controller: controller,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('${games.length} parties · $wins victoires, $draws nulles, $losses défaites'),
        ),
        for (final g in sorted) _GameTile(game: g),
      ],
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.game});

  final GameRecord game;

  @override
  Widget build(BuildContext context) {
    final (letter, color) = switch (game.score) {
      1 => ('V', Colors.green.shade600),
      0 => ('D', Theme.of(context).colorScheme.error),
      _ => ('N', Theme.of(context).colorScheme.outline),
    };
    final result = switch (game.score) {
      1 => 'Victoire',
      0 => 'Défaite',
      _ => 'Nulle',
    };
    final ending = game.ending == Ending.other || game.ending == Ending.draw ? '' : ' ${game.ending.label}';
    final opponent = [
      if (game.opponent != null) game.opponent!,
      if (game.opponentElo != null) '(${game.opponentElo})',
    ].join(' ');
    final link = game.link;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        child: Text(letter),
      ),
      title: Text(opponent.isEmpty ? result : 'contre $opponent'),
      subtitle: Text('${frenchDate(game.date)} · $result$ending'),
      trailing: link == null ? null : const Icon(Icons.open_in_new),
      onTap: link == null
          ? null
          : () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
    );
  }
}
