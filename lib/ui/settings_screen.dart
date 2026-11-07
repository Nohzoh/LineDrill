import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/board_style.dart';
import '../app/providers.dart';

/// Page de création d'un jeton Lichess, sans permission cochée.
final _tokenUrl = Uri.parse('https://lichess.org/account/oauth/token/create?description=LineDrill');

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _token = TextEditingController();
  bool _loaded = false;
  bool _obscure = true;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(lichessTokenProvider.notifier).set(_token.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_token.text.trim().isEmpty ? 'Jeton supprimé' : 'Jeton enregistré')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(lichessTokenProvider);
    if (!_loaded && token.hasValue) {
      _token.text = token.value ?? '';
      _loaded = true;
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const _BoardSection(),
          const SizedBox(height: 32),
          Text('Explorateur Lichess', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'L\'explorateur d\'ouvertures Lichess demande un jeton personnel. '
            'Crée-le sur lichess.org sans cocher aucune permission, puis colle-le ici. '
            'Il reste stocké sur ton téléphone.',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => launchUrl(_tokenUrl, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Créer un jeton sur lichess.org'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _token,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Jeton Lichess',
              hintText: 'lip_…',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Afficher' : 'Masquer',
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      ),
    );
  }
}

/// Choix des couleurs de l'échiquier et des pièces, avec un aperçu.
class _BoardSection extends ConsumerWidget {
  const _BoardSection();

  // Position d'aperçu : 1.e4 e5 2.Nf3 Nc6 3.d4.
  static const _fen = 'r1bqkbnr/pppp1ppp/2n5/4p3/3PP3/5N2/PPP2PPP/RNBQKB1R b KQkq - 0 3';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(boardStyleProvider).value ?? const BoardStyle();
    final notifier = ref.read(boardStyleProvider.notifier);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Échiquier', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Center(
          child: StaticChessboard(
            size: 240,
            orientation: Side.white,
            fen: _fen,
            lastMove: NormalMove.fromUci('d2d4'),
            settings: style.settings,
          ),
        ),
        const SizedBox(height: 16),
        Text('Couleurs', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final t in BoardTheme.values)
              ChoiceChip(
                label: Text(t.label),
                selected: style.theme == t,
                onSelected: (_) => notifier.set(style.copyWith(theme: t)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Pièces', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final p in PieceStyle.values)
              ChoiceChip(
                label: Text(p.label),
                selected: style.pieces == p,
                onSelected: (_) => notifier.set(style.copyWith(pieces: p)),
              ),
          ],
        ),
      ],
    );
  }
}
