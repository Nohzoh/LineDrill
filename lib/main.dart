import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'ui/import_screen.dart';
import 'ui/tree_screen.dart';

void main() {
  runApp(const ProviderScope(child: LineDrillApp()));
}

class LineDrillApp extends StatelessWidget {
  const LineDrillApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
          colorSchemeSeed: const Color(0xFF3D6B4F),
          brightness: brightness,
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'LineDrill',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const _Home(),
    );
  }
}

/// Écran d'import tant qu'aucune partie n'est stockée, arbre ensuite.
class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(gamesProvider);
    return games.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Erreur : $e'))),
      data: (state) => state.games.isEmpty
          ? ImportScreen(initialUsername: state.username)
          : const TreeScreen(),
    );
  }
}
