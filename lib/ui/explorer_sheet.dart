import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/opening_tree.dart';
import '../data/lichess_explorer.dart';
import 'format.dart';
import 'settings_screen.dart';

/// Ouvre l'explorateur Lichess pour [node], atteint par [line].
Future<void> showExplorerSheet(
  BuildContext context, {
  required PositionNode node,
  required List<String> line,
  required Side color,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ExplorerPanel(
        node: node,
        line: line,
        color: color,
        controller: controller,
      ),
    ),
  );
}

/// Coups joués dans la base choisie, avec mes propres stats à côté.
class ExplorerPanel extends ConsumerStatefulWidget {
  const ExplorerPanel({
    super.key,
    required this.node,
    required this.line,
    required this.color,
    this.controller,
  });

  final PositionNode node;
  final List<String> line;
  final Side color;
  final ScrollController? controller;

  @override
  ConsumerState<ExplorerPanel> createState() => _ExplorerPanelState();
}

class _ExplorerPanelState extends ConsumerState<ExplorerPanel> {
  ExplorerDatabase _database = ExplorerDatabase.club;
  Future<ExplorerResult>? _result;
  String? _token;

  void _load(String? token) {
    _token = token;
    _result = ref
        .read(explorerClientProvider)
        .explore(widget.node.position.fen, _database, token: token);
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(lichessTokenProvider).value;
    if (_result == null || token != _token) _load(token);
    final myTurn = widget.node.position.turn == widget.color;
    final reference = ref
        .watch(repertoireProvider)
        .value
        ?.lookup(widget.color, widget.node.key)
        ?.san;

    return ListView(
      controller: widget.controller,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            widget.line.isEmpty ? 'Position initiale' : lineLabel(widget.line),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ExplorerDatabase>(
            segments: [
              for (final db in ExplorerDatabase.values)
                ButtonSegment(value: db, label: Text(db.label)),
            ],
            selected: {_database},
            onSelectionChanged: (s) => setState(() {
              _database = s.first;
              _load(token);
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            _database == ExplorerDatabase.club
                ? 'Parties Lichess bullet et blitz, joueurs de 1000 à 1800.'
                : 'Parties de maîtres.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        FutureBuilder<ExplorerResult>(
          future: _result,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorBox(message: snapshot.error.toString(), missingToken: token == null);
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final result = snapshot.data!;
            if (result.moves.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucune partie dans cette base pour cette position.'),
              );
            }
            return Column(
              children: [
                for (final move in result.moves)
                  _ExplorerTile(
                    label: moveLabel(widget.line.length, move.san),
                    move: move,
                    share: move.total / result.total,
                    color: widget.color,
                    mine: widget.node.move(move.san),
                    isReference: move.san == reference,
                    onChoose: myTurn
                        ? () => ref.read(repertoireProvider.notifier).setReference(
                              widget.color,
                              widget.node.position,
                              move.san,
                              widget.line,
                            )
                        : null,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ExplorerTile extends StatelessWidget {
  const _ExplorerTile({
    required this.label,
    required this.move,
    required this.share,
    required this.color,
    required this.mine,
    required this.isReference,
    required this.onChoose,
  });

  final String label;
  final ExplorerMove move;
  final double share;
  final Side color;
  final MoveStats? mine;
  final bool isReference;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final score = move.scoreFor(color);
    final mineText = mine == null ? '' : ' · moi : ${mine!.count} parties, ${percent(mine!.score)}';
    return ListTile(
      leading: onChoose == null
          ? null
          : IconButton(
              tooltip: isReference ? 'Coup de référence' : 'Choisir comme coup de référence',
              icon: Icon(isReference ? Icons.star : Icons.star_border),
              color: isReference ? Colors.amber.shade700 : null,
              onPressed: onChoose,
            ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${percent(share)} des parties · ${_compact(move.total)}$mineText'),
      trailing: Text(
        percent(score),
        style: TextStyle(color: scoreColor(context, score), fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 1 234 567 → « 1,2 M », 12 345 → « 12 k ».
String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} M';
  if (n >= 10000) return '${(n / 1000).round()} k';
  return '$n';
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.missingToken});

  final String message;
  final bool missingToken;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            child: Text(missingToken ? 'Ajouter mon jeton Lichess' : 'Réglages'),
          ),
        ],
      ),
    );
  }
}
