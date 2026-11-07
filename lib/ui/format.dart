import 'package:flutter/material.dart';

/// `1. e4` pour un coup blanc, `1… e5` pour un coup noir.
String moveLabel(int ply, String san) {
  final number = ply ~/ 2 + 1;
  return ply.isEven ? '$number. $san' : '$number… $san';
}

/// Ligne lisible : `1. e4 g6 2. Nf3`.
String lineLabel(List<String> line) {
  final parts = <String>[];
  for (var i = 0; i < line.length; i++) {
    parts.add(i.isEven ? '${i ~/ 2 + 1}. ${line[i]}' : line[i]);
  }
  return parts.join(' ');
}

String percent(double score) => '${(score * 100).round()} %';

/// Vert au-dessus de 55 %, rouge sous 45 %, neutre entre les deux.
Color scoreColor(BuildContext context, double score) {
  final scheme = Theme.of(context).colorScheme;
  if (score >= 0.55) return Colors.green.shade600;
  if (score <= 0.45) return scheme.error;
  return scheme.outline;
}

/// `2026.10.31` → `31/10/2026`.
String frenchDate(String? date) {
  if (date == null) return '';
  final p = date.split('.');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : date;
}
