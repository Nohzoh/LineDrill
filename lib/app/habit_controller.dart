import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/opening_report.dart';
import '../core/training.dart';
import '../engine/chess_engine.dart';
import 'play_controller.dart';
import 'providers.dart';

/// Temps laissé à Stockfish pour juger un coup, avant de conclure qu'il ne
/// répond plus.
const _patience = Duration(seconds: 30);

/// Nombre d'avis entre deux écritures sur disque : une appli fermée en
/// pleine vérification n'en perd pas plus.
const _saveEvery = 10;

/// Moteur qui refuse une analyse vide. En partie corrigée, `judgeMove` la
/// prend pour « bon coup » et la partie continue ; ici l'avis serait gardé
/// pour de bon, mieux vaut s'arrêter.
class _StrictEngine implements ChessEngine {
  const _StrictEngine(this._engine);

  final ChessEngine _engine;

  @override
  Future<List<EngineLine>> analyse(String fen, {int depth = judgeDepth, int multiPv = 1}) async {
    final lines = await _engine.analyse(fen, depth: depth, multiPv: multiPv);
    if (lines.isEmpty) throw StateError('Stockfish n\'a rien répondu');
    return lines;
  }

  @override
  Future<void> dispose() async {}
}

class HabitCheckState {
  const HabitCheckState({this.running = false, this.color, this.done = 0, this.total = 0, this.error});

  final bool running;

  /// Couleur du bilan vérifié par le dernier lancement.
  final Side? color;

  /// Coups jugés depuis le lancement, sur [total] connus pour l'instant.
  final int done;
  final int total;

  /// Pourquoi la vérification s'est arrêtée avant la fin.
  final String? error;
}

/// Fait juger par Stockfish mes coups habituels du bilan des ouvertures.
class HabitCheckController extends Notifier<HabitCheckState> {
  @override
  HabitCheckState build() => const HabitCheckState();

  /// Juge les coups du bilan affiché qui ne l'ont pas encore été.
  ///
  /// Le bilan est celui de la couleur et du filtre du lancement, même si
  /// l'écran en change avant la fin.
  Future<void> start() async {
    final tree = ref.read(treeProvider);
    if (state.running || tree == null) return;
    final color = ref.read(filterProvider).color;
    state = HabitCheckState(running: true, color: color);
    var done = 0;
    try {
      // Un moteur qui n'a pas démarré est relancé : « Réessayer » doit pouvoir réussir.
      if (ref.read(engineProvider).hasError) ref.invalidate(engineProvider);
      final engine = _StrictEngine(await ref.read(engineProvider.future));
      await ref.read(habitChecksProvider.future);
      final checks = ref.read(habitChecksProvider.notifier);
      // Un avis peut changer le coup à retenir, donc la suite de la variante :
      // on repasse tant que le bilan en demande. [asked] garantit que ça s'arrête.
      final asked = <String>{};
      while (true) {
        final report = openingReport(
          tree,
          color: color,
          repertoire: ref.read(repertoireProvider).value,
          checks: ref.read(habitChecksProvider).value ?? const {},
        );
        final todo = [
          for (final habit in report.unchecked)
            if (asked.add(habit.key)) habit,
        ];
        if (todo.isEmpty) break;
        final total = done + todo.length;
        state = HabitCheckState(running: true, color: color, done: done, total: total);
        final found = <String, HabitCheck>{};
        try {
          for (final habit in todo) {
            final verdict =
                await judgeMove(engine, habit.node.position, habit.move.move, explain: false).timeout(_patience);
            if (!ref.mounted) return;
            found[habit.key] = HabitCheck(verdict.quality, better: verdict.better);
            state = HabitCheckState(running: true, color: color, done: ++done, total: total);
            if (found.length % _saveEvery == 0) await checks.addAll(found);
            if (!ref.mounted) return;
          }
        } finally {
          // Un passage interrompu garde ce qu'il a déjà jugé.
          if (ref.mounted) await checks.addAll(found);
        }
        if (!ref.mounted) return;
      }
      state = HabitCheckState(color: color, done: done, total: done);
    } catch (e) {
      if (ref.mounted) state = HabitCheckState(color: color, done: done, total: done, error: '$e');
    }
  }
}

final habitCheckProvider = NotifierProvider<HabitCheckController, HabitCheckState>(HabitCheckController.new);
