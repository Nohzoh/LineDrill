import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
