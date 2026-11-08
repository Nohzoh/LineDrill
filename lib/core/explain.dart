import 'package:dartchess/dartchess.dart';

import '../engine/chess_engine.dart';

/// Pourquoi un coup est moins bon : ce qu'il permet à l'adversaire, et ce
/// que le meilleur coup aurait apporté. Construit à partir des lignes du
/// moteur, avec quelques motifs reconnus (mat, matériel, fourchette, pièce
/// laissée sans défense, roque perdu) et, à défaut, l'évolution de
/// l'évaluation.
class MoveExplanation {
  const MoveExplanation({
    this.consequences = const [],
    this.missed = const [],
    this.threat,
    this.refutation = '',
    this.bestLine = '',
  });

  /// Ce que mon coup permet (phrases).
  final List<String> consequences;

  /// Ce que le meilleur coup aurait apporté (phrases).
  final List<String> missed;

  /// Réponse adverse la plus forte après mon coup (flèche rouge).
  final Move? threat;

  /// Suite probable après mon coup, en notation, ex. « 3… Nxe4 4. Qxe4 d5 ».
  final String refutation;

  /// Ligne du meilleur coup, même notation.
  final String bestLine;

  bool get isEmpty => consequences.isEmpty && missed.isEmpty;
}

/// Explique pourquoi [move], joué depuis [before], est moins bon que
/// [best].
///
/// [refutation] est la ligne du moteur après mon coup (adversaire au trait)
/// et [playedCp] l'évaluation après mon coup, de mon point de vue.
MoveExplanation explainMove({
  required Position before,
  required Move move,
  required EngineLine best,
  required List<String> refutation,
  required int playedCp,
}) {
  final me = before.turn;
  final after = before.play(move);
  final consequences = <String>[];
  final missed = <String>[];

  // --- Ce que mon coup permet ---------------------------------------------
  final reply = refutation.isEmpty ? null : _parse(after, refutation.first);
  if (playedCp <= -29000) {
    final n = 30000 + playedCp;
    consequences.add(n <= 1
        ? 'L\'adversaire a un mat immédiat : ${_sanLine(after, refutation, 1)}.'
        : 'L\'adversaire a un mat en $n coups : ${_sanLine(after, refutation, 2 * n - 1)}.');
  } else {
    final loss = _materialSwing(before, [move.uci, ...refutation], me);
    // Même garde-fou : la perte doit se voir dans l'évaluation.
    if (loss.mine.isNotEmpty && loss.net <= -1 && best.cp - playedCp >= 60) {
      final firstCapture = _firstCaptureOf(after, refutation, me);
      if (firstCapture != null) {
        final (square, piece) = firstCapture;
        final justMoved = square == _destination(before, move);
        final wasAttacked = !justMoved && before.board.attacksTo(square, me.opposite).isNotEmpty;
        consequences.add(justMoved
            ? '${_capitalize(_mine(piece.role))} que tu viens de jouer en ${square.name} '
                'n\'est pas assez défendu${_agree(piece.role)}.'
            : wasAttacked
                ? '${_capitalize(_mine(piece.role))} en ${square.name} était attaqué${_agree(piece.role)} '
                    'et tu ne l\'as pas mis${_agree(piece.role)} à l\'abri.'
                : '${_capitalize(_mine(piece.role))} en ${square.name} devient vulnérable.');
      }
      consequences.add('Au bout de la suite, tu perds ${_material(loss.mine)}'
          '${loss.theirs.isEmpty ? '' : ' contre ${_material(loss.theirs)}'}.');
    }
    if (reply != null && consequences.isEmpty) {
      final forked = _forkTargets(after.play(reply), _destination(after, reply), me);
      if (forked.length >= 2) {
        final attacker = after.board.pieceAt(_origin(after, reply))!;
        consequences.add('${_capitalize(_theirs(attacker.role))} vient en '
            '${_destination(after, reply).name} et attaque à la fois ${_list(forked.map(_mineOn))}.');
      }
    }
    if (_lostCastling(before, after, move, me)) {
      consequences.add('Tu perds le droit de roquer : ton roi restera exposé.');
    }
    if (consequences.isEmpty) {
      consequences.add('La position se dégrade : ${_evalChange(best.cp, playedCp)}.');
    }
  }

  // --- Ce que le meilleur coup apportait ------------------------------------
  final bestMove = _parse(before, best.uci);
  if (bestMove != null) {
    final bestSan = before.makeSan(bestMove).$2;
    if (best.cp >= 29000) {
      final n = 30000 - best.cp;
      missed.add(n <= 1
          ? 'Tu avais un mat immédiat : $bestSan.'
          : 'Tu avais un mat en $n coups : ${_sanLine(before, best.pv, 2 * n - 1)}.');
    } else {
      final gain = _materialSwing(before, best.pv, me);
      // Un gain n'est annoncé que si le moteur me donne vraiment l'avantage :
      // sinon c'est un échange coupé en plein milieu.
      if (gain.theirs.isNotEmpty && gain.net >= 1 && best.cp >= 80) {
        missed.add('$bestSan gagnait ${_material(gain.theirs)}'
            '${gain.mine.isEmpty ? '' : ' contre ${_material(gain.mine)}'}.');
      } else {
        final forked = _forkTargets(before.play(bestMove), _destination(before, bestMove), me.opposite);
        if (forked.length >= 2) {
          missed.add('$bestSan attaquait à la fois ${_list(forked.map(_theirsOn))}.');
        }
      }
    }
  }

  return MoveExplanation(
    consequences: consequences,
    missed: missed,
    threat: reply,
    refutation: _sanLine(after, refutation, 4),
    bestLine: _sanLine(before, best.pv, 4),
  );
}

// --- Matériel ---------------------------------------------------------------

int _value(Role role) => switch (role) {
      Role.pawn => 1,
      Role.knight || Role.bishop => 3,
      Role.rook => 5,
      Role.queen => 9,
      Role.king => 0,
    };

class _Swing {
  _Swing(this.mine, this.theirs, this.net);

  /// Pièces que je perds / que l'adversaire perd sur la suite.
  final List<Role> mine;
  final List<Role> theirs;

  /// Bilan en points (pion = 1), promotions comprises.
  final int net;
}

/// Bilan matériel de la ligne [ucis] depuis [start], du point de vue de [me].
///
/// On suit au moins 4 demi-coups, puis on s'arrête au premier coup calme,
/// pour ne pas couper un échange en plein milieu.
_Swing _materialSwing(Position start, List<String> ucis, Side me) {
  final initial = _counts(start.board);
  var position = start;
  for (var i = 0; i < ucis.length && i < 12; i++) {
    final move = _parse(position, ucis[i]);
    if (move == null) break;
    if (i >= 4 && !_isCapture(position, move)) break;
    position = position.play(move);
  }
  final end = _counts(position.board);
  int lostCount(Side side, Role role) =>
      ((initial[(side, role)] ?? 0) - (end[(side, role)] ?? 0)).clamp(0, 16);
  // Les échanges pièce contre pièce identique s'annulent : seul le bilan compte.
  List<Role> lost(Side side) => [
        for (final role in Role.values)
          for (var k = 0; k < lostCount(side, role) - lostCount(side.opposite, role); k++) role,
      ];
  int total(Map<(Side, Role), int> counts, Side side) =>
      Role.values.fold(0, (s, r) => s + _value(r) * (counts[(side, r)] ?? 0));
  final net = (total(end, me) - total(initial, me)) - (total(end, me.opposite) - total(initial, me.opposite));
  return _Swing(lost(me), lost(me.opposite), net);
}

Map<(Side, Role), int> _counts(Board board) {
  final counts = <(Side, Role), int>{};
  for (final (_, piece) in board.pieces) {
    counts[(piece.color, piece.role)] = (counts[(piece.color, piece.role)] ?? 0) + 1;
  }
  return counts;
}

bool _isCapture(Position position, Move move) =>
    move is NormalMove &&
    (position.board.pieceAt(move.to)?.color == position.turn.opposite ||
        (position.board.pieceAt(move.from)?.role == Role.pawn && move.from.file != move.to.file));

/// Première prise d'une de mes pièces sur la ligne : case et pièce prise.
(Square, Piece)? _firstCaptureOf(Position start, List<String> ucis, Side me) {
  var position = start;
  for (var i = 0; i < ucis.length && i < 6; i++) {
    final move = _parse(position, ucis[i]);
    if (move is! NormalMove) return null;
    final victim = position.board.pieceAt(move.to);
    if (victim != null && victim.color == me && position.turn != me) return (move.to, victim);
    position = position.play(move);
  }
  return null;
}

// --- Motifs -----------------------------------------------------------------

/// Pièces de [victim] attaquées par la pièce arrivée en [square] et qui
/// valent la peine (pièce plus chère ou non défendue, roi compris).
List<(Square, Piece)> _forkTargets(Position position, Square square, Side victim) {
  final attacker = position.board.pieceAt(square);
  if (attacker == null) return const [];
  final targets = <(Square, Piece)>[];
  for (final target in attacks(attacker, square, position.board.occupied).squares) {
    final piece = position.board.pieceAt(target);
    if (piece == null || piece.color != victim) continue;
    final defended = position.board.attacksTo(target, victim).isNotEmpty;
    if (piece.role == Role.king || _value(piece.role) > _value(attacker.role) || !defended) {
      if (piece.role != Role.pawn) targets.add((target, piece));
    }
  }
  return targets;
}

bool _lostCastling(Position before, Position after, Move move, Side me) {
  final rank = SquareSet.backrankOf(me);
  final had = before.castles.castlingRights.intersect(rank).isNotEmpty;
  final has = after.castles.castlingRights.intersect(rank).isNotEmpty;
  final castled = move is NormalMove &&
      before.board.pieceAt(move.from)?.role == Role.king &&
      (before.board.pieceAt(move.to)?.color == me || (move.from.file - move.to.file).abs() == 2);
  return had && !has && !castled && before.fullmoves <= 20;
}

// --- Évaluation ---------------------------------------------------------------

String _evalChange(int fromCp, int toCp) {
  final from = _evalWords(fromCp);
  final de = from.startsWith('un') ? 'd\'$from' : 'de $from';
  return '$de (${_pawns(fromCp)}) à ${_evalWords(toCp)} (${_pawns(toCp)})';
}

String _evalWords(int cp) {
  final a = cp.abs();
  final side = cp >= 0 ? 'pour toi' : 'pour l\'adversaire';
  if (a < 40) return 'l\'égalité';
  if (a < 120) return 'un léger avantage $side';
  if (a < 300) return 'un net avantage $side';
  return 'un avantage décisif $side';
}

String _pawns(int cp) {
  final value = (cp.clamp(-2000, 2000) / 100).toStringAsFixed(1).replaceAll('.', ',');
  return cp > 0 ? '+$value' : value.replaceAll('-', '−');
}

// --- Notation -----------------------------------------------------------------

Move? _parse(Position position, String uci) {
  final move = Move.parse(uci);
  if (move == null) return null;
  final normalized = move is NormalMove ? position.normalizeMove(move) : move;
  return position.isLegal(normalized) ? normalized : null;
}

Square _destination(Position position, Move move) {
  if (move is! NormalMove) return (move as DropMove).to;
  // Roque noté roi vers tour : le roi arrive en c ou g.
  final piece = position.board.pieceAt(move.from);
  final target = position.board.pieceAt(move.to);
  if (piece?.role == Role.king && target?.color == piece?.color) {
    return Square.fromCoords(move.to.file > move.from.file ? File.g : File.c, move.from.rank);
  }
  return move.to;
}

Square _origin(Position position, Move move) => (move as NormalMove).from;

/// Ligne en notation : « 3… Nxe4 4. Qxe4 d5 », au plus [maxPlies] coups.
String _sanLine(Position start, List<String> ucis, int maxPlies) {
  final parts = <String>[];
  var position = start;
  for (var i = 0; i < ucis.length && i < maxPlies; i++) {
    final move = _parse(position, ucis[i]);
    if (move == null) break;
    final (next, san) = position.makeSan(move);
    final number = position.fullmoves;
    if (position.turn == Side.white) {
      parts.add('$number. $san');
    } else {
      parts.add(i == 0 ? '$number… $san' : san);
    }
    position = next;
  }
  return parts.join(' ');
}

// --- Français -----------------------------------------------------------------

String _name(Role role) => switch (role) {
      Role.pawn => 'pion',
      Role.knight => 'cavalier',
      Role.bishop => 'fou',
      Role.rook => 'tour',
      Role.queen => 'dame',
      Role.king => 'roi',
    };

bool _feminine(Role role) => role == Role.rook || role == Role.queen;

String _agree(Role role) => _feminine(role) ? 'e' : '';

String _mine(Role role) => '${_feminine(role) ? 'ta' : 'ton'} ${_name(role)}';

String _theirs(Role role) => '${_feminine(role) ? 'la' : 'le'} ${_name(role)} adverse';

String _mineOn((Square, Piece) target) => '${_mine(target.$2.role)} (${target.$1.name})';

String _theirsOn((Square, Piece) target) {
  final role = target.$2.role;
  return '${_feminine(role) ? 'la' : 'le'} ${_name(role)} en ${target.$1.name}';
}

/// « un cavalier », « deux pions et une tour ».
String _material(List<Role> roles) {
  final counts = <Role, int>{};
  for (final r in roles) {
    counts[r] = (counts[r] ?? 0) + 1;
  }
  final ordered = counts.keys.toList()..sort((a, b) => _value(b).compareTo(_value(a)));
  const numbers = ['', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit'];
  return _list(ordered.map((r) {
    final n = counts[r]!;
    if (n == 1) return '${_feminine(r) ? 'une' : 'un'} ${_name(r)}';
    return '${n < numbers.length ? numbers[n] : '$n'} ${_name(r)}s';
  }));
}

String _list(Iterable<String> items) {
  final list = items.toList();
  if (list.length <= 1) return list.join();
  return '${list.sublist(0, list.length - 1).join(', ')} et ${list.last}';
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
