import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/core/game_record.dart';
import 'package:linedrill/core/opening_tree.dart';
import 'package:linedrill/core/repertoire.dart';
import 'package:linedrill/core/repertoire_builder.dart';
import 'package:linedrill/engine/chess_engine.dart';

/// Moteur factice : [scores] donne l'évaluation (point de vue du camp qui
/// joue) de certains coups depuis certaines positions, repérées par la
/// suite de coups SAN ; les autres coups valent 0.
class _Engine implements ChessEngine {
  _Engine(this.scores);

  final Map<String, Map<String, int>> scores;
  int calls = 0;

  @override
  Future<List<EngineLine>> analyse(String fen, {int depth = 12, int multiPv = 1}) async {
    calls++;
    final position = Chess.fromSetup(Setup.parseFen(fen));
    final key = _byFen[positionKey(position)] ?? '?';
    final table = scores[key] ?? const {};
    final lines = <EngineLine>[];
    for (final entry in position.legalMoves.entries) {
      for (final to in entry.value.squares) {
        final move = NormalMove(from: entry.key, to: to);
        final san = position.makeSan(move).$2;
        lines.add(EngineLine(move.uci, table[san] ?? 0, [move.uci]));
      }
    }
    lines.sort((a, b) => b.cp.compareTo(a.cp));
    return lines.take(multiPv).toList();
  }

  @override
  Future<void> dispose() async {}

  /// Clé de position → suite SAN, pour retrouver la table de scores.
  static final Map<String, String> _byFen = {};

  static void register(String moves) {
    Position p = Chess.initial;
    for (final san in moves.isEmpty ? const <String>[] : moves.split(' ')) {
      p = p.play(p.parseSan(san)!);
    }
    _byFen[positionKey(p)] = moves;
  }
}

GameRecord _g(String moves, {Side color = Side.white}) =>
    GameRecord(color: color, score: 0.5, timeClass: TimeClass.bullet, sans: moves.split(' '));

List<GameRecord> _n(int n, String moves) => List.generate(n, (_) => _g(moves));

void main() {
  final games = [
    ..._n(6, 'e4 e5 Nf3 Nc6 Bc4'),
    ..._n(4, 'e4 c5 Qh5 Nc6'),
    ..._n(1, 'e4 c5 Nf3 d6'),
    ..._n(2, 'e4 d5 exd5'), // trop rare : non suivi
  ];
  final tree = OpeningTree.build(games, const GameFilter(color: Side.white));

  setUpAll(() {
    for (final m in ['', 'e4 e5', 'e4 e5 Nf3 Nc6', 'e4 c5', 'e4 c5 Qh5', 'e4 c5 Nf3 d6']) {
      _Engine.register(m);
    }
  });

  test('garde les bons coups, corrige les erreurs, suit les réponses fréquentes', () async {
    final engine = _Engine({
      // Après 1.e4 c5 : Qh5 est mauvais, Nf3 est le meilleur.
      'e4 c5': {'Nf3': 40, 'Qh5': -300},
      // Vu des Noirs après 2.Qh5 : Nf6 attaque la dame avec avantage.
      'e4 c5 Qh5': {'Nf6': 300},
      // Après 1.e4 e5 2.Nf3 Nc6 : Bc4 est juste un peu moins bon que Bb5.
      'e4 e5 Nf3 Nc6': {'Bb5': 60, 'Bc4': 0},
    });
    final progress = <int>[];
    final proposals = await buildRepertoire(
      tree: tree,
      engine: engine,
      color: Side.white,
      onProgress: progress.add,
    );
    final byLine = {for (final p in proposals) p.line.join(' '): p};

    expect(byLine['']!.san, 'e4');
    expect(byLine['']!.status, ProposalStatus.kept);
    expect(byLine['']!.reached, 13);

    expect(byLine['e4 e5']!.san, 'Nf3');

    final c5 = byLine['e4 c5']!;
    expect(c5.status, ProposalStatus.corrected);
    expect(c5.usualSan, 'Qh5');
    expect(c5.san, 'Nf3');
    expect(c5.verdict.explanation, isNotNull);

    // Nf3 n'a été joué qu'une fois après 1.e4 c5 : moins que le minimum,
    // la ligne corrigée ne va pas plus loin.
    expect(byLine.containsKey('e4 c5 Nf3 d6'), isFalse);
    // 1.e4 d5 : seulement 2 parties.
    expect(byLine.keys.where((k) => k.startsWith('e4 d5')), isEmpty);

    expect(byLine['e4 e5 Nf3 Nc6']!.status, ProposalStatus.review);
    expect(byLine['e4 e5 Nf3 Nc6']!.san, 'Bc4');
    expect(progress.last, proposals.length);
  });

  test('une erreur qui garde un net avantage est seulement à vérifier', () async {
    // Nf3 donne +9, Qh5 « seulement » +4 : grosse perte, mais toujours gagnant.
    final engine = _Engine({
      'e4 c5': {'Nf3': 900, 'Qh5': 400},
    });
    final proposals = await buildRepertoire(tree: tree, engine: engine, color: Side.white);
    final c5 = proposals.firstWhere((p) => p.line.join(' ') == 'e4 c5');
    expect(c5.status, ProposalStatus.review);
    expect(c5.san, 'Qh5');
    expect(c5.better, 'Nf3');
  });

  test('signale les conflits avec le répertoire existant', () async {
    final existing = Repertoire([
      RepertoireEntry(
        color: Side.white,
        positionKey: tree.follow(['e4', 'e5'])!.key,
        san: 'Bc4',
        line: const ['e4', 'e5'],
      ),
    ]);
    final proposals = await buildRepertoire(
      tree: tree,
      engine: _Engine({}),
      color: Side.white,
      existing: existing,
    );
    final e5 = proposals.firstWhere((p) => p.line.join(' ') == 'e4 e5');
    expect(e5.existing, 'Bc4');
    expect(e5.conflicts, isTrue);
    expect(proposals.where((p) => p.conflicts), hasLength(1));
  });

  test('profondeur maximale et annulation', () async {
    final shallow = await buildRepertoire(
      tree: tree,
      engine: _Engine({}),
      color: Side.white,
      options: const BuilderOptions(maxPly: 1),
    );
    expect(shallow.map((p) => p.line.length), [0]);

    var stop = false;
    final engine = _Engine({});
    final partial = await buildRepertoire(
      tree: tree,
      engine: engine,
      color: Side.white,
      onProgress: (_) => stop = true,
      cancelled: () => stop,
    );
    expect(partial, hasLength(1));
  });

  test('avec les Noirs', () async {
    final black = [
      for (var i = 0; i < 5; i++) _g('e4 d5 exd5 Qxd5 Nc3 Qa5', color: Side.black),
      for (var i = 0; i < 3; i++) _g('d4 d5 c4', color: Side.black),
    ];
    final t = OpeningTree.build(black, const GameFilter(color: Side.black));
    final proposals = await buildRepertoire(tree: t, engine: _Engine({}), color: Side.black);
    expect(proposals.map((p) => '${p.line.join(' ')} → ${p.san}'), [
      'e4 → d5',
      'd4 → d5',
      'e4 d5 exd5 → Qxd5',
      'e4 d5 exd5 Qxd5 Nc3 → Qa5',
    ]);
  });
}
