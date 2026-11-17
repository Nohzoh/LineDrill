import 'package:dartchess/dartchess.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/builder_controller.dart';
import '../app/providers.dart';
import '../core/repertoire_builder.dart';
import 'explanation_view.dart';
import 'format.dart';

/// Préparation automatique du répertoire : mes coups habituels, corrigés
/// par Stockfish quand ils sont mauvais, à valider avant l'ajout.
class BuilderScreen extends ConsumerStatefulWidget {
  const BuilderScreen({super.key});

  @override
  ConsumerState<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends ConsumerState<BuilderScreen> {
  Side? _color;
  late final BuilderController _builder = ref.read(builderProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Repartir d'une page blanche à chaque ouverture.
    Future.microtask(_builder.cancel);
  }

  @override
  void dispose() {
    // Quitter l'écran arrête une analyse en cours (hors de la phase de
    // démontage, où un provider ne peut pas changer).
    final builder = _builder;
    Future.microtask(builder.cancel);
    super.dispose();
  }

  Future<void> _apply() async {
    final added = await ref.read(builderProvider.notifier).apply();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$added coups ajoutés à ton répertoire')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(builderProvider);
    final notifier = ref.read(builderProvider.notifier);
    final color = _color ?? ref.watch(filterProvider).color;
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer mon répertoire')),
      body: s.done
          ? _Results(state: s)
          : s.running
              ? _Progress(analysed: s.analysed, onCancel: notifier.cancel)
              : _Intro(
                  color: color,
                  error: s.error,
                  onColor: (c) => setState(() => _color = c),
                  onStart: () => notifier.start(color),
                ),
      bottomNavigationBar: s.done && s.proposals.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: s.toAdd == 0 ? null : _apply,
                  icon: const Icon(Icons.star),
                  label: Text(s.toAdd == 0
                      ? 'Rien de nouveau à ajouter'
                      : 'Ajouter ${s.toAdd} ${s.toAdd == 1 ? 'coup' : 'coups'} au répertoire'),
                ),
              ),
            )
          : null,
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.color, required this.error, required this.onColor, required this.onStart});

  final Side color;
  final String? error;
  final ValueChanged<Side> onColor;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'LineDrill part de tes parties : dans chaque position que tu as rencontrée au moins '
          '3 fois, il prend le coup que tu joues le plus souvent et le fait juger par Stockfish. '
          'Les bons coups sont gardés, les erreurs sont remplacées par le meilleur coup, avec '
          'l\'explication. Toutes les réponses adverses fréquentes sont suivies.',
        ),
        const SizedBox(height: 8),
        Text(
          'Rien n\'est ajouté sans ta validation, et tes coups de référence actuels ne sont '
          'pas remplacés sans ton accord.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        Text('Couleur', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<Side>(
          segments: const [
            ButtonSegment(value: Side.white, label: Text('Blancs')),
            ButtonSegment(value: Side.black, label: Text('Noirs')),
          ],
          selected: {color},
          onSelectionChanged: (s) => onColor(s.first),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('Analyser mes parties'),
        ),
        const SizedBox(height: 8),
        Text('Compte une à deux minutes.', style: theme.textTheme.bodySmall),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.analysed, required this.onCancel});

  final int analysed;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text('Stockfish analyse tes coups… $analysed '
              '${analysed == 1 ? 'position jugée' : 'positions jugées'}'),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onCancel, child: const Text('Annuler')),
        ],
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.state});

  final BuilderState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    List<Proposal> of(ProposalStatus status) =>
        state.proposals.where((p) => p.status == status).toList();
    final corrected = of(ProposalStatus.corrected);
    final review = of(ProposalStatus.review);
    final kept = of(ProposalStatus.kept);
    final conflicts = state.proposals.where((p) => p.conflicts).length;

    if (state.proposals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Pas assez de parties avec cette couleur : il faut des positions rencontrées au moins 3 fois.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '${state.proposals.length} positions : ${kept.length} coups habituels gardés, '
            '${review.length} à vérifier, ${corrected.length} corrigés.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (conflicts > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              '$conflicts ${conflicts == 1 ? 'proposition diffère' : 'propositions diffèrent'} de ton '
              'répertoire actuel : non cochées par défaut.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        _Section(title: 'Corrigés', subtitle: 'Ton coup habituel est une erreur', proposals: corrected, state: state, initiallyExpanded: true),
        _Section(title: 'À vérifier', subtitle: 'Il y avait mieux, mais ton coup tient', proposals: review, state: state, initiallyExpanded: true),
        _Section(title: 'Coups habituels', subtitle: 'Validés par Stockfish', proposals: kept, state: state, initiallyExpanded: false),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.proposals,
    required this.state,
    required this.initiallyExpanded,
  });

  final String title;
  final String subtitle;
  final List<Proposal> proposals;
  final BuilderState state;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    if (proposals.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      title: Text('$title (${proposals.length})'),
      subtitle: Text(subtitle),
      children: [for (final p in proposals) _ProposalTile(proposal: p, state: state)],
    );
  }
}

class _ProposalTile extends ConsumerStatefulWidget {
  const _ProposalTile({required this.proposal, required this.state});

  final Proposal proposal;
  final BuilderState state;

  @override
  ConsumerState<_ProposalTile> createState() => _ProposalTileState();
}

class _ProposalTileState extends ConsumerState<_ProposalTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.proposal;
    final s = widget.state;
    final notifier = ref.read(builderProvider.notifier);
    final theme = Theme.of(context);
    final chosen = s.chosen(p);
    final already = s.alreadyIn(p);
    final explanation = p.verdict.explanation;
    final better = p.better;
    final hasChoice = better != null && better != p.usualSan && p.status != ProposalStatus.kept;

    final details = <String>[
      'joué ${p.usualCount} fois sur ${p.reached}',
      if (p.status == ProposalStatus.corrected) 'au lieu de ${p.usualSan}',
      if (already)
        'déjà dans ton répertoire'
      else if (p.existing != null && p.existing != chosen)
        'remplacerait ${p.existing}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: already || s.selected.contains(p.key),
          onChanged: already ? null : (_) => notifier.toggle(p.key),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text.rich(
            TextSpan(children: [
              if (p.line.isNotEmpty) TextSpan(text: '${lineLabel(p.line)}  '),
              TextSpan(
                text: moveLabel(p.line.length, chosen),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ]),
          ),
          subtitle: Text(details.join(' · ')),
          secondary: explanation == null || explanation.isEmpty
              ? null
              : IconButton(
                  tooltip: _open ? 'Masquer' : 'Pourquoi ?',
                  icon: Icon(_open ? Icons.expand_less : Icons.help_outline),
                  onPressed: () => setState(() => _open = !_open),
                ),
        ),
        if (hasChoice)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 16, 4),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text('Mon coup : ${p.usualSan}'),
                  selected: chosen == p.usualSan,
                  onSelected: (_) => notifier.choose(p.key, p.usualSan),
                ),
                ChoiceChip(
                  label: Text('Stockfish : $better'),
                  selected: chosen == better,
                  onSelected: (_) => notifier.choose(p.key, better),
                ),
              ],
            ),
          ),
        if (_open && explanation != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
            child: DefaultTextStyle(
              style: theme.textTheme.bodySmall!,
              child: ExplanationView(explanation: explanation),
            ),
          ),
      ],
    );
  }
}
