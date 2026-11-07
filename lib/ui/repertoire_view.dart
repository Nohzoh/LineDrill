import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/drill_controller.dart';
import '../app/providers.dart';
import '../core/drill.dart';
import '../core/repertoire.dart';
import 'format.dart';
import 'drill_screen.dart';
import 'games_sheet.dart';

/// Coups de référence de la couleur filtrée et leur respect dans mes parties.
class RepertoireView extends ConsumerWidget {
  const RepertoireView({super.key, required this.onOpenInTree});

  final VoidCallback onOpenInTree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = ref.watch(filterProvider).color;
    final repertoire = ref.watch(repertoireProvider).value;
    final usage = ref.watch(repertoireUsageProvider);
    if (repertoire == null) return const Center(child: CircularProgressIndicator());

    final entries = repertoire.entries.where((e) => e.color == color).toList()
      ..sort((a, b) {
        final byLength = a.line.length.compareTo(b.line.length);
        return byLength != 0 ? byLength : a.line.join(' ').compareTo(b.line.join(' '));
      });
    final reached = entries.fold<int>(0, (s, e) => s + (usage[e.id]?.reached ?? 0));
    final followed = entries.fold<int>(0, (s, e) => s + (usage[e.id]?.followed.length ?? 0));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            entries.isEmpty
                ? 'Aucun coup de référence avec cette couleur. Dans l\'arbre, touche '
                    'l\'étoile d\'un coup quand c\'est à toi de jouer.'
                : '${entries.length} coups de référence · '
                    '${reached == 0 ? 'pas encore rencontrés dans tes parties' : 'respectés dans ${percent(followed / reached)} des cas'}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (entries.isNotEmpty) const _DrillPanel(),
        for (final entry in entries)
          _EntryCard(
            entry: entry,
            usage: usage[entry.id],
            onOpen: () {
              ref.read(lineProvider.notifier).set(entry.line);
              onOpenInTree();
            },
            onRemove: () => ref.read(repertoireProvider.notifier).remove(entry.color, entry.positionKey),
          ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.usage,
    required this.onOpen,
    required this.onRemove,
  });

  final RepertoireEntry entry;
  final EntryUsage? usage;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = usage;
    final deviated = u?.deviated ?? const <Deviation>[];
    final String status;
    if (u == null || u.reached == 0) {
      status = 'Pas encore rencontré';
    } else {
      final followedText = u.followed.isEmpty ? '' : ' (${percent(u.followedScore!)})';
      final deviatedText = deviated.isEmpty ? '' : ', autre coup ${deviated.length} fois (${percent(u.deviatedScore!)})';
      status = 'Joué ${u.followed.length} fois sur ${u.reached}$followedText$deviatedText';
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: [
                  if (entry.line.isNotEmpty) TextSpan(text: '${lineLabel(entry.line)}  '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.star, size: 18, color: Colors.amber.shade700),
                  ),
                  TextSpan(
                    text: ' ${moveLabel(entry.line.length, entry.san)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ]),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(status, style: theme.textTheme.bodySmall),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (deviated.isNotEmpty)
                    TextButton(
                      onPressed: () => showGamesSheet(
                        context,
                        'Déviations : ${lineLabel(entry.line)}',
                        [for (final d in deviated) d.game],
                      ),
                      child: const Text('Déviations'),
                    ),
                  IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onRemove,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lignes à réviser aujourd'hui et accès aux deux modes de révision.
class _DrillPanel extends ConsumerWidget {
  const _DrillPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueProvider).length;
    final theme = Theme.of(context);
    String subtitle = 'Tout est à jour.';
    if (due == 0) {
      final repertoire = ref.watch(repertoireProvider).value;
      final deck = ref.watch(deckProvider).value;
      final now = ref.watch(clockProvider)();
      final next = repertoire == null || deck == null
          ? null
          : nextDue(repertoire, deck, color: ref.watch(filterProvider).color, now: now);
      if (next != null) subtitle = 'Tout est à jour. Prochaine révision ${_when(next.toLocal(), now)}.';
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              due == 0 ? 'Révisions' : '$due ${due == 1 ? 'ligne' : 'lignes'} à réviser',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(due == 0 ? subtitle : 'Retrouve ton coup dans chaque position ; les lignes ratées reviennent plus souvent.'),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: due == 0 ? null : () => openDrill(context, ref, DrillMode.reflex),
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: const Text('Réflexe (3 s)'),
                ),
                FilledButton.icon(
                  onPressed: due == 0 ? null : () => openDrill(context, ref, DrillMode.learning),
                  icon: const Icon(Icons.school_outlined, size: 18),
                  label: const Text('Réviser'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// « dans 2 h », « demain », « le 12/11 ».
String _when(DateTime date, DateTime now) {
  final local = now.toLocal();
  final diff = date.difference(local);
  if (diff.inMinutes < 60) return 'dans ${diff.inMinutes.clamp(1, 59)} min';
  final today = DateTime(local.year, local.month, local.day);
  final day = DateTime(date.year, date.month, date.day);
  final days = day.difference(today).inDays;
  if (days == 0) return 'dans ${diff.inHours} h';
  if (days == 1) return 'demain';
  return 'le ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}
