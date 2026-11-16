import 'package:dartchess/dartchess.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/habit_controller.dart';
import '../app/providers.dart';
import '../core/opening_report.dart';
import '../core/pgn_import.dart';
import 'format.dart';

/// Bilan de mes ouvertures : ce que je joue le plus, variante par variante,
/// et jusqu'où mes coups sont une habitude.
class OpeningsScreen extends ConsumerWidget {
  const OpeningsScreen({super.key, required this.onOpenInTree});

  /// Appelé après avoir placé l'arbre sur la ligne choisie.
  final VoidCallback onOpenInTree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = ref.watch(filterProvider).color;
    final report = ref.watch(openingReportProvider);
    final unnamed = ref.watch(openingBookProvider).hasError;
    final theme = Theme.of(context);

    void open(List<String> line) {
      ref.read(lineProvider.notifier).set(line);
      Navigator.of(context).pop();
      onOpenInTree();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mes ouvertures')),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SegmentedButton<Side>(
                    segments: const [
                      ButtonSegment(value: Side.white, label: Text('Blancs')),
                      ButtonSegment(value: Side.black, label: Text('Noirs')),
                    ],
                    selected: {color},
                    onSelectionChanged: (s) => ref.read(filterProvider.notifier).setColor(s.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    report.families.isEmpty
                        ? 'Pas encore assez de parties avec cette couleur : une variante compte '
                            'à partir de ${report.minGames} parties. Importe plus de mois.'
                        : 'Tes ouvertures, de la plus jouée à la moins jouée. Une variante compte à partir '
                            'de ${report.minGames} parties ; un coup est connu quand tu le joues au moins '
                            '${(habitShare * 10).round()} fois sur 10.'
                            '${unnamed ? ' Les noms des ouvertures n\'ont pas pu être chargés.' : ''}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (report.families.isNotEmpty) _HabitPanel(report: report, color: color),
                for (final (i, family) in report.families.indexed)
                  _FamilyCard(
                    // Sans clé propre à la couleur, l'état ouvert ou fermé d'une
                    // carte passerait d'une couleur à l'autre.
                    key: PageStorageKey('${color.name} ${family.name}'),
                    family: family,
                    initiallyExpanded: i == 0,
                    onOpen: open,
                  ),
              ],
            ),
    );
  }
}

/// Vérification de mes coups habituels par Stockfish, puis ajout au répertoire.
class _HabitPanel extends ConsumerWidget {
  const _HabitPanel({required this.report, required this.color});

  final OpeningReport report;
  final Side color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(habitCheckProvider);
    final repertoire = ref.watch(repertoireProvider).value;
    if (repertoire == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    // Une vérification, ou son erreur, ne concerne que le bilan (la couleur)
    // où elle a été lancée ; un seul lancement à la fois.
    final here = check.color == color;
    final running = check.running && here;
    final error = here ? check.error : null;
    final String text;
    Widget? action;

    if (running) {
      text = 'Stockfish vérifie tes coups habituels : ${check.done} sur ${check.total}.';
    } else if (report.unchecked.isNotEmpty) {
      text = error != null
          ? 'Vérification impossible : $error'
          : 'Stockfish peut vérifier tes coups habituels et remplacer ceux qui perdent du terrain, '
              'avant d\'en faire ton répertoire.'
              '${check.running ? ' Il termine d\'abord l\'autre couleur.' : ''}';
      action = FilledButton.icon(
        onPressed: check.running ? null : () => ref.read(habitCheckProvider.notifier).start(),
        icon: const Icon(Icons.fact_check_outlined, size: 18),
        label: Text(error != null ? 'Réessayer' : 'Vérifier mes coups'),
      );
    } else {
      final entries = habitEntries(report, color, repertoire);
      final fixes = report.steps.where((s) => s.status == HabitStatus.toFix).length;
      if (entries.isEmpty) {
        text = 'Rien à ajouter : là où ton répertoire te mène, chaque position a déjà son coup de référence.';
      } else {
        final verdict = switch (fixes) {
          0 => 'rien à corriger',
          1 => '1 coup à corriger',
          _ => '$fixes coups à corriger',
        };
        text = 'Coups vérifiés par Stockfish : $verdict. Ajoute-les à ton répertoire pour les réviser.';
        final n = entries.length;
        action = FilledButton.icon(
          onPressed: () async {
            await ref.read(repertoireProvider.notifier).addMissing(entries);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${n == 1 ? '1 coup ajouté' : '$n coups ajoutés'}. Révise-les dans l\'onglet Répertoire.'),
            ));
          },
          icon: const Icon(Icons.star, size: 18),
          label: Text(n == 1 ? 'Ajouter 1 coup au répertoire' : 'Ajouter $n coups au répertoire'),
        );
      }
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            if (running)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(value: check.total == 0 ? 0 : check.done / check.total),
              ),
            if (action != null) Align(alignment: Alignment.centerRight, child: action),
          ],
        ),
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({super.key, required this.family, required this.initiallyExpanded, required this.onOpen});

  final OpeningFamily family;
  final bool initiallyExpanded;
  final ValueChanged<List<String>> onOpen;

  @override
  Widget build(BuildContext context) {
    final depths = [for (final v in family.variants) v.knownDepth]..sort();
    final depth = depths.first == depths.last
        ? _known(depths.first)
        : 'de ${depths.first} à ${_known(depths.last)} selon la variante';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(family.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text.rich(TextSpan(children: [
          TextSpan(text: '${family.count} parties · '),
          TextSpan(
            text: percent(family.score),
            style: TextStyle(color: scoreColor(context, family.score), fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' · $depth'),
        ])),
        children: [
          for (final variant in family.variants) ...[
            const Divider(height: 1),
            _VariantTile(variant: variant, onOpen: onOpen),
          ],
        ],
      ),
    );
  }
}

class _VariantTile extends StatelessWidget {
  const _VariantTile({required this.variant, required this.onOpen});

  final OpeningVariant variant;
  final ValueChanged<List<String>> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gap = variant.gap;
    final known = variant.knownDepth;
    final total = variant.steps.length;
    final line = lineLabel(variant.line);
    // Sans nom de variante, la ligne elle-même distingue les variantes.
    final variation = variant.name?.variation;
    return InkWell(
      // La position où mon habitude s'arrête, sinon la fin de la variante.
      onTap: () => onOpen(gap?.line ?? variant.line),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(variation ?? line, style: theme.textTheme.titleSmall)),
                const SizedBox(width: 8),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${variant.count} parties · '),
                    TextSpan(
                      text: percent(variant.score),
                      style: TextStyle(color: scoreColor(context, variant.score), fontWeight: FontWeight.w600),
                    ),
                  ]),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (variation != null) ...[
              const SizedBox(height: 2),
              Text(line, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : known / total,
                      minHeight: 4,
                      color: Colors.green.shade600,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  known < total ? '${_known(known)} sur $total' : _known(known),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_gapText(variant), style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// « 1 coup connu », « 4 coups connus ».
String _known(int n) => switch (n) {
      0 => 'aucun coup connu',
      1 => '1 coup connu',
      _ => '$n coups connus',
    };

/// Pourquoi mes coups acquis s'arrêtent là.
String _gapText(OpeningVariant variant) {
  final gap = variant.gap;
  if (gap == null) {
    return variant.line.length >= maxPlies
        ? 'Connue jusqu\'au bout des ${maxPlies ~/ 2} coups suivis par l\'arbre.'
        : 'Au-delà, pas assez de parties pour juger.';
  }
  final ply = gap.line.length;
  final played = '${moveLabel(ply, gap.played.san)} (${percent(gap.share)})';
  if (gap.status == HabitStatus.offRepertoire) {
    return 'Ton répertoire prévoit ${moveLabel(ply, gap.reference)}, tu joues surtout $played.';
  }
  if (gap.status == HabitStatus.toFix) {
    return 'Tu joues $played : ${gap.check!.quality.label.toLowerCase()}. Mieux : ${moveLabel(ply, gap.reference)}.';
  }
  // Hésitation : un autre coup prend forcément le reste des parties.
  final other = gap.alternative!;
  return 'Ensuite tu hésites : $played ou ${moveLabel(ply, other.san)} (${percent(other.count / gap.reached)}).';
}
