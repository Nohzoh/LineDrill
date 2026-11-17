import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/opening_tree.dart';
import '../core/repertoire.dart';
import '../core/repertoire_builder.dart';
import 'play_controller.dart';
import 'providers.dart';

class BuilderState {
  const BuilderState({
    this.color = Side.white,
    this.running = false,
    this.done = false,
    this.analysed = 0,
    this.proposals = const [],
    this.choices = const {},
    this.selected = const {},
    this.error,
  });

  final Side color;
  final bool running;
  final bool done;

  /// Positions déjà jugées par Stockfish.
  final int analysed;

  final List<Proposal> proposals;

  /// Coup retenu par position (clé de position) : la proposition, ou l'autre
  /// coup si je l'ai changé.
  final Map<String, String> choices;

  /// Positions cochées pour l'ajout au répertoire.
  final Set<String> selected;

  final String? error;

  String chosen(Proposal p) => choices[p.key] ?? p.san;

  /// Déjà dans le répertoire avec ce coup : rien à ajouter.
  bool alreadyIn(Proposal p) => p.existing == chosen(p);

  int get toAdd => proposals.where((p) => selected.contains(p.key) && !alreadyIn(p)).length;

  BuilderState copyWith({
    bool? running,
    bool? done,
    int? analysed,
    List<Proposal>? proposals,
    Map<String, String>? choices,
    Set<String>? selected,
    String? Function()? error,
  }) =>
      BuilderState(
        color: color,
        running: running ?? this.running,
        done: done ?? this.done,
        analysed: analysed ?? this.analysed,
        proposals: proposals ?? this.proposals,
        choices: choices ?? this.choices,
        selected: selected ?? this.selected,
        error: error != null ? error() : this.error,
      );
}

/// Préparation automatique du répertoire à partir de mes parties.
class BuilderController extends Notifier<BuilderState> {
  int _run = 0;

  @override
  BuilderState build() => const BuilderState();

  /// Lance l'analyse pour [color], sur les parties du filtre de cadence.
  Future<void> start(Side color) async {
    final run = ++_run;
    state = BuilderState(color: color, running: true);
    try {
      final games = ref.read(gamesProvider).value?.games ?? const [];
      final filter = ref.read(filterProvider).copyWith(color: color);
      final tree = OpeningTree.build(games, filter);
      final engine = await ref.read(engineProvider.future);
      final repertoire = ref.read(repertoireProvider).value ?? await ref.read(repertoireProvider.future);
      final proposals = await buildRepertoire(
        tree: tree,
        engine: engine,
        color: color,
        existing: repertoire,
        onProgress: (n) {
          if (run == _run && ref.mounted) state = state.copyWith(analysed: n);
        },
        cancelled: () => run != _run || !ref.mounted,
      );
      if (run != _run || !ref.mounted) return;
      state = state.copyWith(
        running: false,
        done: true,
        proposals: proposals,
        // Par défaut tout est coché, sauf ce qui remplacerait un coup de
        // référence que j'ai déjà choisi.
        selected: {for (final p in proposals) if (!p.conflicts) p.key},
      );
    } catch (e) {
      if (run != _run || !ref.mounted) return;
      state = state.copyWith(running: false, error: () => 'Analyse impossible : $e');
    }
  }

  void cancel() {
    _run++;
    // Peut arriver après la destruction de l'appli (annulation différée).
    if (!ref.mounted) return;
    state = BuilderState(color: state.color);
  }

  void toggle(String key) {
    final selected = {...state.selected};
    if (!selected.remove(key)) selected.add(key);
    state = state.copyWith(selected: selected);
  }

  /// Choisit [san] pour la position [key] (coup habituel ou coup du moteur).
  void choose(String key, String san) =>
      state = state.copyWith(choices: {...state.choices, key: san}, selected: {...state.selected, key});

  /// Ajoute les positions cochées au répertoire ; renvoie le nombre ajouté.
  Future<int> apply() async {
    final entries = [
      for (final p in state.proposals)
        if (state.selected.contains(p.key) && !state.alreadyIn(p))
          RepertoireEntry(
            color: state.color,
            positionKey: p.key,
            san: state.chosen(p),
            line: List.unmodifiable(p.line),
          ),
    ];
    await ref.read(repertoireProvider.notifier).addAll(entries);
    return entries.length;
  }
}

final builderProvider = NotifierProvider<BuilderController, BuilderState>(BuilderController.new);
