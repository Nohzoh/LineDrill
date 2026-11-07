import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/opening_tree.dart';
import '../core/repertoire.dart';
import '../core/training.dart';
import '../engine/chess_engine.dart';
import '../engine/stockfish_engine.dart';
import 'providers.dart';

/// Moteur partagé, lancé à la première partie et arrêté avec l'appli.
final engineProvider = FutureProvider<ChessEngine>((ref) async {
  final engine = await startStockfish();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Derniers réglages de partie (couleur et niveau), mémorisés dans les réglages.
class PlaySetup {
  const PlaySetup({this.color, this.level = OpponentLevel.easy});

  /// `null` : suivre la couleur du filtre, tant que rien n'a été choisi.
  final Side? color;
  final OpponentLevel level;

  Map<String, Object?> toJson() => {
        if (color != null) 'color': color!.name,
        'level': level.name,
      };

  factory PlaySetup.fromJson(Map<String, Object?> json) => PlaySetup(
        color: Side.values.asNameMap()[json['color']],
        level: OpponentLevel.values.asNameMap()[json['level']] ?? OpponentLevel.easy,
      );
}

class PlaySetupNotifier extends AsyncNotifier<PlaySetup> {
  @override
  Future<PlaySetup> build() async {
    final settings = await (await ref.watch(repertoireStoreProvider.future)).settings();
    final play = settings['play'];
    return play is Map ? PlaySetup.fromJson(play.cast<String, Object?>()) : const PlaySetup();
  }

  Future<void> set({Side? color, OpponentLevel? level}) async {
    // État courant s'il est chargé : deux choix rapprochés ne s'écrasent pas.
    final current = state.value ?? await future;
    final next = PlaySetup(color: color ?? current.color, level: level ?? current.level);
    state = AsyncData(next);
    await (await ref.read(repertoireStoreProvider.future)).updateSetting('play', next.toJson());
  }
}

final playSetupProvider = AsyncNotifierProvider<PlaySetupNotifier, PlaySetup>(PlaySetupNotifier.new);

/// Hasard des choix adverses (remplaçable en test).
final randomProvider = Provider<math.Random>((ref) => math.Random());

/// Profondeur d'analyse pour juger mes coups.
const _judgeDepth = 12;

enum PlayPhase {
  /// Je joue mes coups de référence contre les réponses de mes vraies parties.
  repertoire('Répertoire'),

  /// Stockfish joue et juge mes coups.
  engine('Stockfish');

  const PlayPhase(this.label);

  final String label;
}

class PlayedMove {
  const PlayedMove(this.san, this.side, {this.quality});

  final String san;
  final Side side;

  /// Qualité, pour mes coups seulement.
  final MoveQuality? quality;
}

/// Coup joué qui attend ma décision : rejouer ou continuer.
class PendingCorrection {
  const PendingCorrection(this.before, this.move, this.san, this.verdict, this.previousMove);

  final Position before;

  /// Dernier coup affiché avant le mien (celui de l'adversaire).
  final Move? previousMove;
  final Move move;
  final String san;
  final MoveVerdict verdict;
}

class PlayState {
  const PlayState({
    this.started = false,
    this.userColor = Side.white,
    this.level = OpponentLevel.easy,
    this.position = Chess.initial,
    this.moves = const [],
    this.lastMove,
    this.phase = PlayPhase.repertoire,
    this.thinking = false,
    this.pending,
    this.lastVerdict,
    this.message,
    this.result,
    this.corrections = 0,
  });

  final bool started;
  final Side userColor;
  final OpponentLevel level;
  final Position position;
  final List<PlayedMove> moves;
  final Move? lastMove;
  final PlayPhase phase;

  /// Le moteur réfléchit (à mon coup ou au sien).
  final bool thinking;

  final PendingCorrection? pending;

  /// Verdict sur mon dernier coup accepté.
  final MoveVerdict? lastVerdict;

  /// Information ponctuelle (changement de phase, erreur moteur…).
  final String? message;

  /// Fin de partie, en clair.
  final String? result;

  /// Nombre de coups corrigés pendant la partie.
  final int corrections;

  bool get myTurn =>
      started && result == null && pending == null && !thinking && position.turn == userColor;

  PlayState copyWith({
    Position? position,
    List<PlayedMove>? moves,
    Move? lastMove,
    PlayPhase? phase,
    bool? thinking,
    PendingCorrection? Function()? pending,
    MoveVerdict? Function()? lastVerdict,
    String? Function()? message,
    String? result,
    int? corrections,
  }) =>
      PlayState(
        started: started,
        userColor: userColor,
        level: level,
        position: position ?? this.position,
        moves: moves ?? this.moves,
        lastMove: lastMove ?? this.lastMove,
        phase: phase ?? this.phase,
        thinking: thinking ?? this.thinking,
        pending: pending != null ? pending() : this.pending,
        lastVerdict: lastVerdict != null ? lastVerdict() : this.lastVerdict,
        message: message != null ? message() : this.message,
        result: result ?? this.result,
        corrections: corrections ?? this.corrections,
      );
}

/// Partie corrigée : répertoire d'abord, puis Stockfish à la sortie.
class PlayController extends Notifier<PlayState> {
  /// Change à chaque nouvelle partie, pour ignorer les analyses en retard.
  int _gameId = 0;
  OpeningTree? _book;
  Repertoire _repertoire = Repertoire();

  /// L'adversaire joue encore des réponses tirées de mes vraies parties.
  bool _opponentInBook = true;

  @override
  PlayState build() => const PlayState();

  Future<ChessEngine> get _engine => ref.read(engineProvider.future);

  /// Démarre une partie ; si je joue les Noirs, l'adversaire commence.
  Future<void> start(Side color, OpponentLevel level) async {
    final id = ++_gameId;
    final games = ref.read(gamesProvider).value?.games ?? const [];
    _book = OpeningTree.build(games, GameFilter(color: color));
    _repertoire = ref.read(repertoireProvider).value ?? Repertoire();
    _opponentInBook = true;
    state = PlayState(started: true, userColor: color, level: level);
    _checkStillInRepertoire();
    if (color == Side.black) await _opponentTurn(id);
  }

  /// Nouvelle partie avec la même couleur et le même niveau.
  Future<void> restart() => start(state.userColor, state.level);

  /// Retour aux réglages de partie.
  void stop() {
    _gameId++;
    state = const PlayState();
  }

  /// Mon coup, joué sur l'échiquier.
  Future<void> play(Move move) async {
    if (!state.myTurn) return;
    final before = state.position;
    if (!before.isLegal(move)) return;
    if (move is NormalMove) move = before.normalizeMove(move);
    final id = _gameId;
    final previousMove = state.lastMove;
    final (after, san) = before.makeSan(move);

    if (state.phase == PlayPhase.repertoire) {
      final entry = _repertoire.lookup(state.userColor, positionKey(before));
      if (entry != null && entry.san == san) {
        _commitMine(after, move, san, const MoveVerdict(MoveQuality.book));
        await _opponentTurn(id);
        return;
      }
      if (entry != null) {
        state = state.copyWith(
          position: after,
          lastMove: move,
          pending: () => PendingCorrection(
            before,
            move,
            san,
            MoveVerdict(MoveQuality.offBook, better: entry.san),
            previousMove,
          ),
          message: () => null,
        );
        return;
      }
    }

    state = state.copyWith(position: after, lastMove: move, thinking: true, message: () => null);
    final MoveVerdict verdict;
    try {
      verdict = await judgeMove(await _engine, before, move, depth: _judgeDepth);
    } catch (e) {
      if (id != _gameId) return;
      // Sans moteur, on accepte le coup sans le juger et la partie continue.
      state = state.copyWith(thinking: false, message: () => 'Analyse impossible : $e');
      _commitMine(after, move, san, const MoveVerdict(MoveQuality.good));
      await _opponentTurn(id);
      return;
    }
    if (id != _gameId) return;
    if (verdict.quality.needsCorrection) {
      state = state.copyWith(
        thinking: false,
        pending: () => PendingCorrection(before, move, san, verdict, previousMove),
      );
      return;
    }
    state = state.copyWith(thinking: false);
    _commitMine(after, move, san, verdict);
    await _opponentTurn(id);
  }

  /// Annule le coup corrigé pour en jouer un autre.
  void retry() {
    final pending = state.pending;
    if (pending == null) return;
    state = PlayState(
      started: true,
      userColor: state.userColor,
      level: state.level,
      position: pending.before,
      moves: state.moves,
      lastMove: pending.previousMove,
      phase: state.phase,
      corrections: state.corrections + 1,
    );
  }

  /// Garde le coup corrigé et continue la partie.
  Future<void> keep() async {
    final pending = state.pending;
    if (pending == null) return;
    final id = _gameId;
    // Quitter son répertoire fait passer la partie en phase moteur.
    if (pending.verdict.quality == MoveQuality.offBook) {
      state = state.copyWith(phase: PlayPhase.engine);
    }
    state = state.copyWith(pending: () => null, corrections: state.corrections + 1);
    _commitMine(state.position, pending.move, pending.san, pending.verdict);
    await _opponentTurn(id);
  }

  void _commitMine(Position after, Move move, String san, MoveVerdict verdict) {
    state = state.copyWith(
      position: after,
      lastMove: move,
      moves: [...state.moves, PlayedMove(san, state.userColor, quality: verdict.quality)],
      lastVerdict: () => verdict,
    );
    _checkGameOver();
  }

  Future<void> _opponentTurn(int id) async {
    if (state.result != null || state.position.turn == state.userColor) return;
    final position = state.position;
    Move? move;

    // Tant que la position figure dans mes parties, l'adversaire y joue
    // une réponse réelle, que je sois encore dans mon répertoire ou non.
    if (_opponentInBook) {
      final reply = pickBookMove(_book?.node(positionKey(position)), ref.read(randomProvider));
      if (reply != null && position.isLegal(reply.move)) {
        move = reply.move;
      } else {
        _opponentInBook = false;
        state = state.copyWith(
          phase: PlayPhase.engine,
          message: () => 'Position absente de tes parties : Stockfish joue pour l\'adversaire.',
        );
      }
    }

    if (move == null) {
      state = state.copyWith(thinking: true);
      try {
        final engine = await _engine;
        final lines = await engine.analyse(
          position.fen,
          depth: state.level.depth,
          multiPv: state.level.multiPv,
        );
        if (id != _gameId) return;
        move = engineMove(position, pickEngineMove(lines, state.level, ref.read(randomProvider)).uci);
      } catch (e) {
        if (id != _gameId) return;
        state = state.copyWith(thinking: false, message: () => 'Stockfish indisponible : $e');
        return;
      }
    }
    if (id != _gameId) return;

    final (after, san) = position.makeSan(move);
    state = state.copyWith(
      position: after,
      lastMove: move,
      thinking: false,
      moves: [...state.moves, PlayedMove(san, position.turn)],
    );
    _checkGameOver();
    _checkStillInRepertoire();
  }

  /// En phase répertoire, sans coup de référence ici, Stockfish prend le relais.
  void _checkStillInRepertoire() {
    if (state.phase != PlayPhase.repertoire || state.result != null) return;
    if (state.position.turn != state.userColor) return;
    if (_repertoire.lookup(state.userColor, positionKey(state.position)) == null) {
      state = state.copyWith(
        phase: PlayPhase.engine,
        message: () => 'Fin de ton répertoire : à partir d\'ici, Stockfish juge tes coups.',
      );
    }
  }

  void _checkGameOver() {
    final position = state.position;
    if (!position.isGameOver) return;
    final String result;
    if (position.isCheckmate) {
      result = position.turn == state.userColor ? 'Échec et mat, perdu.' : 'Échec et mat, gagné !';
    } else if (position.isStalemate) {
      result = 'Pat : partie nulle.';
    } else {
      result = 'Partie nulle.';
    }
    state = state.copyWith(result: result, thinking: false);
  }
}

final playProvider = NotifierProvider<PlayController, PlayState>(PlayController.new);
