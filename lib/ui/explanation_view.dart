import 'package:flutter/material.dart';

import '../core/explain.dart';

/// Couleurs des flèches : meilleur coup / réponse adverse.
const arrowGreen = Color(0xcc15781b);
const arrowRed = Color(0xccb3261e);

/// Conséquences de mon coup, puis ce que le meilleur coup apportait.
class ExplanationView extends StatelessWidget {
  const ExplanationView({
    super.key,
    required this.explanation,
    this.showsArrows = false,
  });

  final MoveExplanation explanation;

  /// Les flèches sont visibles sur l'échiquier (coup en attente).
  final bool showsArrows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
    Widget line(String label, String moves, Color color) => Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label : ', style: small),
            TextSpan(
              text: moves,
              style: small?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in explanation.consequences) bullet(c),
        if (explanation.refutation.isNotEmpty)
          line(
            showsArrows
                ? 'Suite probable (flèche rouge)'
                : 'Suite probable après ton coup',
            explanation.refutation,
            arrowRed,
          ),
        for (final m in explanation.missed) bullet(m),
        if (explanation.bestLine.isNotEmpty)
          line('Ligne conseillée', explanation.bestLine, arrowGreen),
      ],
    );
  }
}
