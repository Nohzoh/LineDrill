import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/opening_tree.dart';
import 'format.dart';
import 'games_sheet.dart';

/// Navigation dans l'arbre des ouvertures, avec le score de chaque coup.
class TreeView extends ConsumerWidget {
  const TreeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(treeProvider);
    final filter = ref.watch(filterProvider);
    final username = ref.watch(gamesProvider).value?.username;
    if (tree == null) return const Center(child: CircularProgressIndicator());
    final setLine = ref.read(lineProvider.notifier).set;

    // La ligne peut disparaître quand le filtre change : on remonte
    // jusqu'à la dernière position encore présente.
    var line = ref.watch(lineProvider);
    while (line.isNotEmpty && tree.follow(line) == null) {
      line = line.sublist(0, line.length - 1);
    }
    final node = tree.follow(line)!;
    final parent = line.isEmpty ? null : tree.follow(line.sublist(0, line.length - 1));
    final reached = parent?.move(line.last);

    return LayoutBuilder(
      builder: (context, constraints) {
        final boardSize = constraints.maxWidth.clamp(0, 480).toDouble();
        return ListView(
          children: [
            _Summary(tree: tree, username: username),
            Center(
              child: StaticChessboard(
                size: boardSize,
                orientation: filter.color,
                fen: node.position.fen,
                lastMove: reached?.move,
              ),
            ),
            _LineBar(line: line, onSelect: setLine),
            if (reached != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '  Cette ligne : ${reached.count} parties · ${percent(reached.score)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => showGamesSheet(context, lineLabel(line), reached.games),
                      icon: const Icon(Icons.list, size: 18),
                      label: const Text('Parties'),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            if (node.moves.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucune partie ne va plus loin dans cette ligne.'),
              ),
            for (final stats in node.moves)
              _MoveTile(
                label: moveLabel(line.length, stats.san),
                stats: stats,
                onTap: () => setLine([...line, stats.san]),
              ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.tree, required this.username});

  final OpeningTree tree;
  final String? username;

  @override
  Widget build(BuildContext context) {
    final n = tree.games.length;
    final text = n == 0
        ? 'Aucune partie pour ce filtre.'
        : '${username ?? ''} · $n parties · score ${percent(tree.score)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

/// Coups de la ligne courante ; un tap revient à cette position.
class _LineBar extends StatelessWidget {
  const _LineBar({required this.line, required this.onSelect});

  final List<String> line;
  final ValueChanged<List<String>> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (var i = line.length - 1; i >= 0; i--)
            TextButton(
              onPressed: () => onSelect(line.sublist(0, i + 1)),
              child: Text(moveLabel(i, line[i])),
            ),
          IconButton(
            tooltip: 'Position initiale',
            icon: const Icon(Icons.first_page),
            onPressed: line.isEmpty ? null : () => onSelect(const []),
          ),
        ],
      ),
    );
  }
}

class _MoveTile extends StatelessWidget {
  const _MoveTile({required this.label, required this.stats, required this.onTap});

  final String label;
  final MoveStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scoreColor(context, stats.score);
    return ListTile(
      onTap: onTap,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: stats.score,
            minHeight: 4,
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(percent(stats.score), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          Text('${stats.count} parties', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
