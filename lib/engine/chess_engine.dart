import 'dart:async';

/// Une ligne d'analyse : premier coup en UCI et évaluation en centipions,
/// du point de vue du camp au trait, avec la suite prévue ([pv], en UCI,
/// premier coup compris).
class EngineLine {
  const EngineLine(this.uci, this.cp, [List<String>? pv]) : pv = pv ?? const [];

  final String uci;
  final int cp;
  final List<String> pv;

  @override
  String toString() => '$uci ($cp)';
}

/// Moteur d'échecs vu par l'appli : analyse d'une position.
abstract class ChessEngine {
  /// Meilleures lignes de [fen], de la meilleure à la moins bonne.
  Future<List<EngineLine>> analyse(String fen, {int depth = 12, int multiPv = 1});

  Future<void> dispose();
}

/// Valeur donnée à un mat en N demi-coups : très grande, mais un mat plus
/// rapide vaut mieux qu'un mat plus lent.
int mateScore(int mateIn) => mateIn > 0 ? 30000 - mateIn : -30000 - mateIn;

/// Moteur UCI générique : on écrit des commandes, on lit les lignes produites.
///
/// Les analyses sont traitées une à la fois, dans l'ordre des demandes.
class UciEngine implements ChessEngine {
  UciEngine({
    required Stream<String> output,
    required this._send,
    this._onDispose,
  }) {
    _subscription = output.listen(_onLine);
  }

  final void Function(String) _send;
  final Future<void> Function()? _onDispose;
  late final StreamSubscription<String> _subscription;

  Future<void> _queue = Future.value();
  _Search? _current;

  @override
  Future<List<EngineLine>> analyse(String fen, {int depth = 12, int multiPv = 1}) {
    final result = _queue.then((_) => _run(fen, depth, multiPv));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<EngineLine>> _run(String fen, int depth, int multiPv) {
    final search = _Search(multiPv);
    _current = search;
    _send('setoption name MultiPV value $multiPv');
    _send('position fen $fen');
    _send('go depth $depth');
    return search.done.future;
  }

  void _onLine(String line) {
    final search = _current;
    if (search == null) return;
    if (line.startsWith('bestmove')) {
      _current = null;
      search.finish();
    } else if (line.startsWith('info ')) {
      search.read(line);
    }
  }

  @override
  Future<void> dispose() async {
    await _subscription.cancel();
    await _onDispose?.call();
  }
}

class _Search {
  _Search(this.multiPv);

  final int multiPv;
  final done = Completer<List<EngineLine>>();
  final Map<int, EngineLine> _lines = {};

  /// `info depth 12 seldepth 18 multipv 2 score cp -34 nodes … pv e7e5 g1f3 …`
  void read(String line) {
    final tokens = line.split(' ');
    var pvIndex = 1;
    int? cp;
    List<String>? pv;
    var bound = false;
    for (var i = 0; i < tokens.length; i++) {
      switch (tokens[i]) {
        case 'multipv':
          pvIndex = int.tryParse(tokens[i + 1]) ?? 1;
        case 'score':
          final kind = tokens[i + 1];
          final value = int.tryParse(tokens[i + 2]);
          if (value != null) cp = kind == 'mate' ? mateScore(value) : value;
        case 'lowerbound' || 'upperbound':
          bound = true;
        case 'pv':
          pv = tokens.sublist(i + 1).where((t) => t.isNotEmpty).toList();
          i = tokens.length;
      }
    }
    if (cp != null && pv != null && pv.isNotEmpty && !bound) {
      _lines[pvIndex] = EngineLine(pv.first, cp, pv);
    }
  }

  void finish() {
    final keys = _lines.keys.toList()..sort();
    done.complete([for (final k in keys) _lines[k]!]);
  }
}
