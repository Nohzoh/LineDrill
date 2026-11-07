import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/board_style.dart';
import '../app/providers.dart';
import '../core/opening_tree.dart';
import '../core/repertoire.dart';
import 'explorer_sheet.dart';
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
    final style = ref.watch(boardStyleProvider).value ?? const BoardStyle();
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
    final myTurn = node.position.turn == filter.color;
    final reference = myTurn
        ? ref.watch(repertoireProvider).value?.lookup(filter.color, node.key)
        : null;
    final usage = reference == null ? null : ref.watch(repertoireUsageProvider)[reference.id];
    final repertoire = ref.read(repertoireProvider.notifier);
    void explore() => showExplorerSheet(context, node: node, line: line, color: filter.color);

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
                settings: style.settings,
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
            if (myTurn)
              _ReferencePanel(
                reference: reference,
                usage: usage,
                line: line,
                onExplore: explore,
                onRemove: reference == null
                    ? null
                    : () => repertoire.remove(filter.color, node.key),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    onPressed: explore,
                    icon: const Icon(Icons.travel_explore, size: 18),
                    label: const Text('Explorateur'),
                  ),
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
                isReference: reference?.san == stats.san,
                onStar: myTurn
                    ? () => repertoire.setReference(filter.color, node.position, stats.san, line)
                    : null,
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
  const _MoveTile({
    required this.label,
    required this.stats,
    required this.onTap,
    this.isReference = false,
    this.onStar,
  });

  final String label;
  final MoveStats stats;
  final VoidCallback onTap;
  final bool isReference;

  /// Choisit ce coup comme référence ; `null` quand c'est à l'adversaire.
  final VoidCallback? onStar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scoreColor(context, stats.score);
    return ListTile(
      onTap: onTap,
      leading: onStar == null
          ? null
          : IconButton(
              tooltip: isReference ? 'Coup de référence' : 'Choisir comme coup de référence',
              icon: Icon(isReference ? Icons.star : Icons.star_border),
              color: isReference ? Colors.amber.shade700 : null,
              onPressed: onStar,
            ),
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

/// Coup de référence de la position, quand c'est à moi de jouer.
class _ReferencePanel extends StatelessWidget {
  const _ReferencePanel({
    required this.reference,
    required this.usage,
    required this.line,
    required this.onExplore,
    required this.onRemove,
  });

  final RepertoireEntry? reference;
  final EntryUsage? usage;
  final List<String> line;
  final VoidCallback onExplore;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ref = reference;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ref == null ? Icons.star_border : Icons.star,
                  color: ref == null ? theme.colorScheme.outline : Colors.amber.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ref == null
                        ? 'Pas encore de coup de référence ici'
                        : 'Mon coup : ${moveLabel(line.length, ref.san)}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (usage != null && usage!.reached > 0) ...[
              const SizedBox(height: 6),
              _UsageText(usage: usage!),
            ],
            if (ref == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Touche l\'étoile d\'un coup, ou cherche une idée dans l\'explorateur.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                if (onRemove != null) TextButton(onPressed: onRemove, child: const Text('Retirer')),
                if (usage != null && usage!.deviated.isNotEmpty)
                  TextButton(
                    onPressed: () => showGamesSheet(
                      context,
                      'Déviations : ${lineLabel(line)}',
                      [for (final d in usage!.deviated) d.game],
                    ),
                    child: const Text('Déviations'),
                  ),
                TextButton.icon(
                  onPressed: onExplore,
                  icon: const Icon(Icons.travel_explore, size: 18),
                  label: const Text('Explorateur'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// « Joué dans 12 parties (58 %) · autre coup dans 5 parties (20 %) : Nf3 ×3, Bc4 ×2 »
class _UsageText extends StatelessWidget {
  const _UsageText({required this.usage});

  final EntryUsage usage;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (usage.followed.isNotEmpty) {
      parts.add('Joué dans ${usage.followed.length} parties (${percent(usage.followedScore!)})');
    }
    if (usage.deviated.isNotEmpty) {
      final counts = <String, int>{};
      for (final d in usage.deviated) {
        counts[d.played] = (counts[d.played] ?? 0) + 1;
      }
      final played = (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .map((e) => '${e.key} ×${e.value}')
          .join(', ');
      parts.add('autre coup dans ${usage.deviated.length} parties '
          '(${percent(usage.deviatedScore!)}) : $played');
    }
    return Text(parts.join(' · '), style: Theme.of(context).textTheme.bodySmall);
  }
}
