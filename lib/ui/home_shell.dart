import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/game_record.dart';
import 'import_screen.dart';
import 'play_view.dart';
import 'repertoire_view.dart';
import 'settings_screen.dart';
import 'tree_view.dart';
import 'weak_lines_view.dart';

/// Écran principal : filtres communs et onglets Arbre, Points faibles, Répertoire, Jouer.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final gamesState = ref.watch(gamesProvider).value;
    final line = ref.watch(lineProvider);
    final canPop = _tab == 0 && line.isEmpty;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab != 0) {
          setState(() => _tab = 0);
        } else {
          ref.read(lineProvider.notifier).set(line.sublist(0, line.length - 1));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LineDrill'),
          actions: [
            IconButton(
              tooltip: 'Importer',
              icon: const Icon(Icons.sync),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ImportScreen(initialUsername: gamesState?.username),
              )),
            ),
            IconButton(
              tooltip: 'Réglages',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_tab != 3) const _Filters(),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  const TreeView(),
                  WeakLinesView(onOpenInTree: () => setState(() => _tab = 0)),
                  RepertoireView(onOpenInTree: () => setState(() => _tab = 0)),
                  const PlayView(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.account_tree_outlined), label: 'Arbre'),
            NavigationDestination(icon: Icon(Icons.trending_down), label: 'Points faibles'),
            NavigationDestination(icon: Icon(Icons.star_outline), label: 'Répertoire'),
            NavigationDestination(icon: Icon(Icons.sports_esports_outlined), label: 'Jouer'),
          ],
        ),
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final games = ref.watch(gamesProvider).value?.games ?? const [];
    final classes = {for (final g in games) g.timeClass}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final notifier = ref.read(filterProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<Side>(
              segments: const [
                ButtonSegment(value: Side.white, label: Text('Blancs')),
                ButtonSegment(value: Side.black, label: Text('Noirs')),
              ],
              selected: {filter.color},
              onSelectionChanged: (s) => notifier.setColor(s.first),
            ),
            if (classes.length > 1)
              for (final TimeClass c in classes)
                FilterChip(
                  label: Text(c.label),
                  selected: filter.timeClasses.contains(c),
                  onSelected: (_) => notifier.toggleTimeClass(c),
                ),
          ],
        ),
      ),
    );
  }
}
