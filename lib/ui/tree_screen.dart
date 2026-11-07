import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/game_record.dart';
import '../core/opening_tree.dart';
import 'import_screen.dart';

/// Navigation dans l'arbre des ouvertures, avec le score de chaque coup.
class TreeScreen extends ConsumerStatefulWidget {
  const TreeScreen({super.key});

  @override
  ConsumerState<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends ConsumerState<TreeScreen> {
  /// Ligne affichée, en SAN depuis la position initiale.
  List<String> _line = const [];

  void _goTo(List<String> line) => setState(() => _line = line);

  @override
  Widget build(BuildContext context) {
    final gamesState = ref.watch(gamesProvider).value;
    final filter = ref.watch(filterProvider);
    final tree = ref.watch(treeProvider);
    if (gamesState == null || tree == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // La ligne peut disparaître quand le filtre change : on remonte
    // jusqu'à la dernière position encore présente.
    var line = _line;
    while (line.isNotEmpty && tree.follow(line) == null) {
      line = line.sublist(0, line.length - 1);
    }
    final node = tree.follow(line)!;
    final parent = line.isEmpty ? null : tree.follow(line.sublist(0, line.length - 1));
    final lastMove = parent?.move(line.last)?.move;
    final classes = {for (final g in gamesState.games) g.timeClass}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return PopScope(
      canPop: line.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(line.sublist(0, line.length - 1));
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LineDrill'),
          actions: [
            IconButton(
              tooltip: 'Importer',
              icon: const Icon(Icons.sync),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ImportScreen(initialUsername: gamesState.username),
              )),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final boardSize = constraints.maxWidth.clamp(0, 480).toDouble();
            return ListView(
              children: [
                _Filters(filter: filter, classes: classes),
                _Summary(tree: tree, username: gamesState.username),
                Center(
                  child: StaticChessboard(
                    size: boardSize,
                    orientation: filter.color,
                    fen: node.position.fen,
                    lastMove: lastMove,
                  ),
                ),
                _LineBar(line: line, onSelect: _goTo),
                if (node.moves.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Aucune partie ne va plus loin dans cette ligne.'),
                  ),
                for (final stats in node.moves)
                  _MoveTile(
                    label: _moveLabel(line.length, stats.san),
                    stats: stats,
                    onTap: () => _goTo([...line, stats.san]),
                  ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// `1. e4` pour un coup blanc, `1… e5` pour un coup noir.
String _moveLabel(int ply, String san) {
  final number = ply ~/ 2 + 1;
  return ply.isEven ? '$number. $san' : '$number… $san';
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.filter, required this.classes});

  final GameFilter filter;
  final List<TimeClass> classes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(filterProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<Side>(
            segments: const [
              ButtonSegment(value: Side.white, label: Text('Blancs')),
              ButtonSegment(value: Side.black, label: Text('Noirs')),
            ],
            selected: {filter.color},
            onSelectionChanged: (s) => notifier.setColor(s.first),
          ),
          if (classes.length > 1)
            for (final c in classes)
              FilterChip(
                label: Text(c.label),
                selected: filter.timeClasses.contains(c),
                onSelected: (_) => notifier.toggleTimeClass(c),
              ),
        ],
      ),
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
        : '${username ?? ''} · $n parties · score ${_percent(tree.score)}';
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
              child: Text(_moveLabel(i, line[i])),
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
    final color = stats.score >= 0.55
        ? Colors.green.shade600
        : stats.score <= 0.45
            ? scheme.error
            : scheme.outline;
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
          Text(_percent(stats.score), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          Text('${stats.count} parties', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

String _percent(double score) => '${(score * 100).round()} %';
