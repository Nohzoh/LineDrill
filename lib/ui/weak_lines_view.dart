import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/weak_lines.dart';
import 'format.dart';
import 'games_sheet.dart';

/// Lignes où l'utilisateur perd le plus de points.
class WeakLinesView extends ConsumerWidget {
  const WeakLinesView({super.key, required this.onOpenInTree});

  /// Appelé après avoir placé l'arbre sur la ligne choisie.
  final VoidCallback onOpenInTree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(treeProvider);
    final lines = ref.watch(weakLinesProvider);
    final color = ref.watch(filterProvider).color;
    final repertoire = ref.watch(repertoireProvider).value;
    if (tree == null) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Lignes jouées au moins 10 fois, classées par points perdus '
            'sous ta moyenne (${percent(tree.score)}).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (lines.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Aucune ligne faible avec ce filtre. Bravo, ou importe plus de parties.'),
          ),
        for (final (i, line) in lines.indexed)
          _WeakLineCard(
            rank: i + 1,
            line: line,
            orientation: color,
            fen: tree.follow(line.line)!.position.fen,
            reference: line.lastMoveIsOpponent(color == Side.white)
                ? repertoire?.lookup(color, tree.follow(line.line)!.key)?.san
                : null,
            onOpen: () {
              ref.read(lineProvider.notifier).set(line.line);
              onOpenInTree();
            },
          ),
      ],
    );
  }
}

class _WeakLineCard extends StatelessWidget {
  const _WeakLineCard({
    required this.rank,
    required this.line,
    required this.orientation,
    required this.fen,
    required this.reference,
    required this.onOpen,
  });

  final int rank;
  final WeakLine line;
  final Side orientation;
  final String fen;

  /// Mon coup de référence après cette ligne, s'il existe.
  final String? reference;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = line.stats;
    final opponentMove = line.lastMoveIsOpponent(orientation == Side.white);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StaticChessboard(
                size: 88,
                orientation: orientation,
                fen: fen,
                lastMove: stats.move,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '#$rank  ', style: TextStyle(color: theme.colorScheme.outline)),
                        TextSpan(text: lineLabel(line.line)),
                      ]),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      !opponentMove
                          ? 'Ton coup te coûte des points'
                          : reference == null
                              ? 'Réponse adverse : que jouer ici ?'
                              : 'Réponse adverse · mon coup prévu : ${moveLabel(line.line.length, reference!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text.rich(TextSpan(children: [
                      TextSpan(
                        text: percent(stats.score),
                        style: TextStyle(
                          color: scoreColor(context, stats.score),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: ' · ${stats.count} parties · '
                            '−${line.cost.toStringAsFixed(1).replaceAll('.', ',')} pts',
                      ),
                    ])),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => showGamesSheet(context, lineLabel(line.line), stats.games),
                        icon: const Icon(Icons.list, size: 18),
                        label: const Text('Parties'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
