import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/board_style.dart';
import '../app/drill_controller.dart';
import '../app/providers.dart';
import '../core/drill.dart';
import 'format.dart';

/// Lance une séance de révision et ouvre son écran.
Future<void> openDrill(BuildContext context, WidgetRef ref, DrillMode mode) async {
  final color = ref.read(filterProvider).color;
  await ref.read(drillProvider.notifier).start(mode, color);
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DrillScreen()));
  ref.read(drillProvider.notifier).stop();
}

class DrillScreen extends ConsumerStatefulWidget {
  const DrillScreen({super.key});

  @override
  ConsumerState<DrillScreen> createState() => _DrillScreenState();
}

class _DrillScreenState extends ConsumerState<DrillScreen> {
  late final ChessboardController _board = ChessboardController(game: _gameData(ref.read(drillProvider)));

  /// Délai avant la question suivante après un coup juste.
  static const _advanceDelay = Duration(milliseconds: 700);
  Timer? _advance;

  static GameData _gameData(DrillState s) {
    final position = s.position ?? Chess.initial;
    final card = s.card;
    return GameData(
      fen: position.fen,
      lastMove: s.feedback == DrillFeedback.correct ? s.played : card?.lastMove,
      playerSide: s.color == Side.white ? PlayerSide.white : PlayerSide.black,
      sideToMove: position.turn,
      kingSquareInCheck: position.isCheck ? position.board.kingOf(position.turn) : null,
      validMoves: s.canPlay ? makeLegalMoves(position) : const {},
    );
  }

  @override
  void dispose() {
    _advance?.cancel();
    _board.dispose();
    super.dispose();
  }

  void _onChange(DrillState? previous, DrillState next) {
    _board.updatePosition(_gameData(next));
    // Coup juste : on enchaîne tout seul, sauf s'il fallait corriger.
    if (next.feedback == DrillFeedback.correct && previous?.feedback != DrillFeedback.correct) {
      final index = next.index;
      _advance?.cancel();
      _advance = Timer(_advanceDelay, () {
        if (mounted && ref.read(drillProvider).index == index) ref.read(drillProvider.notifier).next();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(drillProvider, _onChange);
    final s = ref.watch(drillProvider);
    final style = ref.watch(boardStyleProvider).value ?? const BoardStyle();
    final notifier = ref.read(drillProvider.notifier);
    final card = s.card;

    final shapes = <Shape>{};
    if (card != null && (s.feedback == DrillFeedback.wrong || s.feedback == DrillFeedback.timeout)) {
      final answer = card.position.parseSan(card.entry.san);
      if (answer is NormalMove) {
        shapes.add(Arrow(color: const Color(0xcc15781b), orig: answer.from, dest: answer.to));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Révision · ${s.mode.label}'),
        actions: [
          if (s.cards.isNotEmpty && !s.finished)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${s.index + 1} / ${s.cards.length}'),
              ),
            ),
        ],
      ),
      body: s.finished || card == null
          ? _Summary(state: s)
          : LayoutBuilder(
              builder: (context, constraints) {
                final boardSize = constraints.maxWidth.clamp(0, 480).toDouble();
                return ListView(
                  children: [
                    _Prompt(card: card, color: s.color),
                    if (s.mode == DrillMode.reflex)
                      _ReflexTimer(
                        key: ValueKey(s.index),
                        running: s.feedback == DrillFeedback.none,
                        onTimeout: notifier.timeout,
                      ),
                    Center(
                      child: Chessboard(
                        size: boardSize,
                        controller: _board,
                        orientation: s.color,
                        settings: style.interactiveSettings,
                        shapes: shapes,
                        onMove: (move, {viaDragAndDrop}) => notifier.attempt(move),
                      ),
                    ),
                    _Feedback(state: s, onNext: notifier.next),
                  ],
                );
              },
            ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.card, required this.color});

  final DrillCard card;
  final Side color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.entry.line.isEmpty ? 'Position initiale' : lineLabel(card.entry.line),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Ton coup avec les ${color == Side.white ? 'Blancs' : 'Noirs'} ?',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Barre qui se vide en [reflexLimit] ; à zéro, la question est ratée.
class _ReflexTimer extends StatefulWidget {
  const _ReflexTimer({super.key, required this.running, required this.onTimeout});

  final bool running;
  final VoidCallback onTimeout;

  @override
  State<_ReflexTimer> createState() => _ReflexTimerState();
}

class _ReflexTimerState extends State<_ReflexTimer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: reflexLimit)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onTimeout();
    })
    ..forward();

  @override
  void didUpdateWidget(_ReflexTimer old) {
    super.didUpdateWidget(old);
    if (!widget.running) _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => LinearProgressIndicator(
        value: 1 - _controller.value,
        minHeight: 6,
        color: _controller.value > 0.66 ? scheme.error : scheme.primary,
        backgroundColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.state, required this.onNext});

  final DrillState state;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final card = state.card!;
    final answer = moveLabel(card.entry.line.length, card.entry.san);
    final theme = Theme.of(context);
    final (String text, Color? color, bool showNext) = switch (state.feedback) {
      DrillFeedback.none => ('', null, false),
      DrillFeedback.correct => ('Juste : $answer', Colors.green.shade700, false),
      DrillFeedback.wrong => state.mode == DrillMode.learning
          ? ('Non : c\'est $answer (flèche verte). Joue-le pour continuer.', theme.colorScheme.error, false)
          : ('Non : c\'était $answer.', theme.colorScheme.error, true),
      DrillFeedback.timeout => ('Temps écoulé : c\'était $answer.', theme.colorScheme.error, true),
    };
    if (text.isEmpty) return const SizedBox(height: 56);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: color)),
          ),
          if (showNext) FilledButton(onPressed: onNext, child: const Text('Suivant')),
        ],
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.state});

  final DrillState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final total = state.correct + state.wrong;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          state.cards.isEmpty ? 'Rien à réviser pour l\'instant.' : 'Séance terminée',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (total > 0)
          Text('${state.correct} justes sur $total · les lignes ratées reviendront bientôt.'),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Terminer'),
        ),
      ],
    );
  }
}
