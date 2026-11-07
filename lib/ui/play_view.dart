import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/board_style.dart';
import '../app/play_controller.dart';
import '../app/providers.dart';
import '../core/training.dart';

/// Partie corrigée : réglages, puis partie avec correction coup par coup.
class PlayView extends ConsumerWidget {
  const PlayView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final started = ref.watch(playProvider.select((s) => s.started));
    return started ? const _GameView() : const _SetupView();
  }
}

class _SetupView extends ConsumerStatefulWidget {
  const _SetupView();

  @override
  ConsumerState<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends ConsumerState<_SetupView> {
  Side? _color;
  OpponentLevel _level = OpponentLevel.easy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _color ?? ref.watch(filterProvider).color;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Partie corrigée', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'L\'adversaire joue d\'abord les réponses de tes vraies parties, et toi tes coups '
          'de référence. À la sortie de ton répertoire, Stockfish prend le relais et juge '
          'chacun de tes coups : en cas d\'erreur, il te montre mieux et tu peux rejouer.',
        ),
        const SizedBox(height: 24),
        Text('Je joue', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<Side>(
          segments: const [
            ButtonSegment(value: Side.white, label: Text('Blancs')),
            ButtonSegment(value: Side.black, label: Text('Noirs')),
          ],
          selected: {color},
          onSelectionChanged: (s) => setState(() => _color = s.first),
        ),
        const SizedBox(height: 20),
        Text('Adversaire', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<OpponentLevel>(
          segments: [
            for (final l in OpponentLevel.values) ButtonSegment(value: l, label: Text(l.label)),
          ],
          selected: {_level},
          onSelectionChanged: (s) => setState(() => _level = s.first),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => ref.read(playProvider.notifier).start(color, _level),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Commencer'),
        ),
      ],
    );
  }
}

class _GameView extends ConsumerStatefulWidget {
  const _GameView();

  @override
  ConsumerState<_GameView> createState() => _GameViewState();
}

class _GameViewState extends ConsumerState<_GameView> {
  late final ChessboardController _board = ChessboardController(game: _gameData(ref.read(playProvider)));

  static GameData _gameData(PlayState s) => GameData(
        fen: s.position.fen,
        lastMove: s.lastMove,
        playerSide: s.userColor == Side.white ? PlayerSide.white : PlayerSide.black,
        sideToMove: s.position.turn,
        kingSquareInCheck: s.position.isCheck ? s.position.board.kingOf(s.position.turn) : null,
        validMoves: s.myTurn ? makeLegalMoves(s.position) : const {},
      );

  @override
  void dispose() {
    _board.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playProvider, (_, next) => _board.updatePosition(_gameData(next)));
    final s = ref.watch(playProvider);
    final style = ref.watch(boardStyleProvider).value ?? const BoardStyle();
    final notifier = ref.read(playProvider.notifier);

    final pending = s.pending;
    final shapes = <Shape>{};
    final better = pending?.verdict.better;
    if (pending != null && better != null) {
      final move = pending.before.parseSan(better);
      if (move is NormalMove) {
        shapes.add(Arrow(color: const Color(0xcc15781b), orig: move.from, dest: move.to));
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final boardSize = constraints.maxWidth.clamp(0, 480).toDouble();
        return ListView(
          children: [
            _StatusBar(state: s, onNewGame: notifier.stop),
            Center(
              child: Chessboard(
                size: boardSize,
                controller: _board,
                orientation: s.userColor,
                settings: style.interactiveSettings,
                shapes: shapes,
                onMove: (move, {viaDragAndDrop}) => notifier.play(move),
              ),
            ),
            if (pending != null)
              _CorrectionCard(
                pending: pending,
                moveNumber: s.moves.length,
                onRetry: notifier.retry,
                onKeep: notifier.keep,
              )
            else if (s.result != null)
              _ResultCard(result: s.result!, corrections: s.corrections, onNewGame: notifier.stop)
            else if (s.lastVerdict != null)
              _VerdictLine(verdict: s.lastVerdict!),
            if (s.message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(s.message!, style: Theme.of(context).textTheme.bodySmall),
              ),
            _MoveList(moves: s.moves),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state, required this.onNewGame});

  final PlayState state;
  final VoidCallback onNewGame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String status;
    if (state.result != null) {
      status = 'Partie terminée';
    } else if (state.thinking) {
      status = state.position.turn == state.userColor ? 'Analyse de ton coup…' : 'Stockfish réfléchit…';
    } else if (state.pending != null) {
      status = 'Coup à corriger';
    } else {
      status = state.myTurn ? 'À toi de jouer' : 'Au tour de l\'adversaire';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Chip(
            avatar: Icon(
              state.phase == PlayPhase.repertoire ? Icons.star : Icons.memory,
              size: 18,
            ),
            label: Text(state.phase.label),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 12),
          if (state.thinking) ...[
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(status, style: theme.textTheme.bodyMedium)),
          IconButton(
            tooltip: 'Nouvelle partie',
            icon: const Icon(Icons.restart_alt),
            onPressed: onNewGame,
          ),
        ],
      ),
    );
  }
}

/// « 3. Cg5 ?? Gaffe. Mieux : 3. Fb5 », avec Rejouer et Continuer.
class _CorrectionCard extends StatelessWidget {
  const _CorrectionCard({
    required this.pending,
    required this.moveNumber,
    required this.onRetry,
    required this.onKeep,
  });

  final PendingCorrection pending;

  /// Nombre de demi-coups déjà joués avant le coup corrigé.
  final int moveNumber;
  final VoidCallback onRetry;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verdict = pending.verdict;
    final offBook = verdict.quality == MoveQuality.offBook;
    final color = verdict.quality == MoveQuality.blunder ? theme.colorScheme.error : Colors.orange.shade800;
    final played = _label(moveNumber, pending.san);
    final better = verdict.better == null ? null : _label(moveNumber, verdict.better!);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${verdict.quality.label} : $played',
              style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
            if (better != null) ...[
              const SizedBox(height: 4),
              Text(offBook ? 'Ton coup prévu : $better' : 'Mieux : $better (flèche verte)'),
            ],
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: onKeep,
                  child: Text(offBook ? 'Garder mon coup' : 'Continuer quand même'),
                ),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.undo),
                  label: const Text('Rejouer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VerdictLine extends StatelessWidget {
  const _VerdictLine({required this.verdict});

  final MoveVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (verdict.quality) {
      MoveQuality.book => (Icons.star, Colors.amber.shade700),
      MoveQuality.good => (Icons.check_circle, Colors.green.shade600),
      MoveQuality.inaccuracy => (Icons.info, Colors.orange.shade700),
      _ => (Icons.error, Theme.of(context).colorScheme.error),
    };
    final hint = verdict.quality == MoveQuality.inaccuracy && verdict.better != null
        ? ' : ${verdict.better} était un peu mieux'
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('${verdict.quality.label}$hint')),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.corrections, required this.onNewGame});

  final String result;
  final int corrections;
  final VoidCallback onNewGame;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(corrections == 0 ? 'Aucune correction.' : '$corrections coups corrigés.'),
            const SizedBox(height: 8),
            FilledButton(onPressed: onNewGame, child: const Text('Nouvelle partie')),
          ],
        ),
      ),
    );
  }
}

/// Coups de la partie, mes coups annotés selon leur qualité.
class _MoveList extends StatelessWidget {
  const _MoveList({required this.moves});

  final List<PlayedMove> moves;

  @override
  Widget build(BuildContext context) {
    if (moves.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final spans = <InlineSpan>[];
    for (final (i, m) in moves.indexed) {
      if (i.isEven) spans.add(TextSpan(text: '${i ~/ 2 + 1}. ', style: TextStyle(color: theme.colorScheme.outline)));
      final mark = switch (m.quality) {
        MoveQuality.inaccuracy => '?!',
        MoveQuality.mistake || MoveQuality.offBook => '?',
        MoveQuality.blunder => '??',
        _ => '',
      };
      spans.add(TextSpan(
        text: '${m.san}$mark ',
        style: TextStyle(fontWeight: m.side == moves.first.side ? FontWeight.w600 : FontWeight.w400),
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text.rich(TextSpan(children: spans), style: theme.textTheme.bodyMedium),
    );
  }
}

String _label(int ply, String san) {
  final number = ply ~/ 2 + 1;
  return ply.isEven ? '$number. $san' : '$number… $san';
}
