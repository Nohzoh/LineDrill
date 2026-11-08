import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:linedrill/engine/chess_engine.dart';

void main() {
  test('lit les lignes multipv à la dernière profondeur', () async {
    final out = StreamController<String>();
    final sent = <String>[];
    final engine = UciEngine(output: out.stream, send: sent.add);

    final result = engine.analyse('fen1', depth: 10, multiPv: 2);
    await Future<void>.delayed(Duration.zero);
    expect(sent, ['setoption name MultiPV value 2', 'position fen fen1', 'go depth 10']);

    out
      ..add('info depth 9 multipv 1 score cp 20 nodes 10 pv e2e4 e7e5')
      ..add('info depth 10 multipv 1 score cp 35 lowerbound nodes 12 pv d2d4')
      ..add('info depth 10 multipv 1 score cp 30 nodes 12 pv e2e4 e7e5')
      ..add('info depth 10 multipv 2 score cp 12 nodes 12 pv d2d4 d7d5')
      ..add('bestmove e2e4 ponder e7e5');
    final lines = await result;
    expect(lines.map((l) => '${l.uci} ${l.cp}'), ['e2e4 30', 'd2d4 12']);
    expect(lines.first.pv, ['e2e4', 'e7e5']);
  });

  test('mat converti en très grand score', () async {
    final out = StreamController<String>();
    final engine = UciEngine(output: out.stream, send: (_) {});
    final result = engine.analyse('fen', multiPv: 2);
    await Future<void>.delayed(Duration.zero);
    out
      ..add('info depth 5 multipv 1 score mate 2 pv d8h4')
      ..add('info depth 5 multipv 2 score mate -3 pv a7a6')
      ..add('bestmove d8h4');
    final lines = await result;
    expect(lines.first.cp, 29998);
    expect(lines.last.cp, -29997);
    expect(lines.first.cp > lines.last.cp, isTrue);
  });

  test('analyses en file, une à la fois', () async {
    final out = StreamController<String>();
    final sent = <String>[];
    final engine = UciEngine(output: out.stream, send: sent.add);
    final a = engine.analyse('A');
    final b = engine.analyse('B');
    await Future<void>.delayed(Duration.zero);
    expect(sent.where((s) => s.startsWith('position')), ['position fen A']);
    out
      ..add('info depth 1 score cp 1 pv a2a3')
      ..add('bestmove a2a3');
    expect((await a).single.uci, 'a2a3');
    await Future<void>.delayed(Duration.zero);
    expect(sent.where((s) => s.startsWith('position')), ['position fen A', 'position fen B']);
    out
      ..add('info depth 1 score cp 2 pv b2b3')
      ..add('bestmove b2b3');
    expect((await b).single.uci, 'b2b3');
  });
}
