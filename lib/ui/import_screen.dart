import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// Saisie du pseudo Chess.com et import des parties.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, this.initialUsername});

  final String? initialUsername;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  late final _username = TextEditingController(text: widget.initialUsername);
  int _monthsBack = 3;
  bool _busy = false;
  double? _progress;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final name = _username.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Saisis ton pseudo Chess.com.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      await ref.read(gamesProvider.notifier).sync(
            name,
            monthsBack: _monthsBack,
            onProgress: (done, total) {
              if (mounted) setState(() => _progress = total == 0 ? 1 : done / total);
            },
          );
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importer mes parties')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _username,
            enabled: !_busy,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _import(),
            decoration: const InputDecoration(
              labelText: 'Pseudo Chess.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('Période', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1 mois')),
              ButtonSegment(value: 3, label: Text('3 mois')),
              ButtonSegment(value: 6, label: Text('6 mois')),
              ButtonSegment(value: 12, label: Text('12 mois')),
            ],
            selected: {_monthsBack},
            onSelectionChanged: _busy ? null : (s) => setState(() => _monthsBack = s.first),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.download),
            label: const Text('Importer'),
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            LinearProgressIndicator(value: _progress),
          ],
          if (_error != null) ...[
            const SizedBox(height: 24),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
