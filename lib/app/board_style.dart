import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

/// Couleurs d'échiquier proposées.
enum BoardTheme {
  green('Vert'),
  brown('Marron'),
  blue('Bleu');

  const BoardTheme(this.label);

  final String label;

  ChessboardColorScheme get scheme => switch (this) {
        BoardTheme.green => _greenScheme,
        BoardTheme.brown => ChessboardColorScheme.brown,
        BoardTheme.blue => ChessboardColorScheme.blue,
      };
}

/// Jeux de pièces proposés (sous licence libre, fournis par chessground).
enum PieceStyle {
  staunty('Staunty', PieceSet.staunty),
  cburnett('Classique', PieceSet.cburnett),
  maestro('Maestro', PieceSet.maestro),
  california('California', PieceSet.california),
  merida('Merida', PieceSet.merida);

  const PieceStyle(this.label, this.set);

  final String label;
  final PieceSet set;
}

/// Apparence de l'échiquier choisie par l'utilisateur.
class BoardStyle {
  const BoardStyle({this.theme = BoardTheme.green, this.pieces = PieceStyle.staunty});

  final BoardTheme theme;
  final PieceStyle pieces;

  StaticChessboardSettings get settings => StaticChessboardSettings(
        colorScheme: theme.scheme,
        pieceAssets: pieces.set.assets,
        enableCoordinates: true,
      );

  /// Réglages pour une miniature : sans coordonnées, illisibles à cette taille.
  StaticChessboardSettings get thumbnailSettings => StaticChessboardSettings(
        colorScheme: theme.scheme,
        pieceAssets: pieces.set.assets,
      );

  /// Réglages de l'échiquier jouable (pas de prémouvement).
  ChessboardSettings get interactiveSettings => ChessboardSettings(
        colorScheme: theme.scheme,
        pieceAssets: pieces.set.assets,
        enableCoordinates: true,
        enablePremoves: false,
      );

  BoardStyle copyWith({BoardTheme? theme, PieceStyle? pieces}) =>
      BoardStyle(theme: theme ?? this.theme, pieces: pieces ?? this.pieces);

  Map<String, Object?> toJson() => {'theme': theme.name, 'pieces': pieces.name};

  factory BoardStyle.fromJson(Map<String, Object?> json) => BoardStyle(
        theme: BoardTheme.values.asNameMap()[json['theme']] ?? BoardTheme.green,
        pieces: PieceStyle.values.asNameMap()[json['pieces']] ?? PieceStyle.staunty,
      );
}

// Vert clair et vert foncé, avec le dernier coup surligné en jaune.
const _light = Color(0xffebecd0);
const _dark = Color(0xff739552);

const _greenScheme = ChessboardColorScheme(
  lightSquare: _light,
  darkSquare: _dark,
  background: SolidColorChessboardBackground(lightSquare: _light, darkSquare: _dark),
  whiteCoordBackground: SolidColorChessboardBackground(
    lightSquare: _light,
    darkSquare: _dark,
    coordinates: true,
  ),
  blackCoordBackground: SolidColorChessboardBackground(
    lightSquare: _light,
    darkSquare: _dark,
    coordinates: true,
    orientation: Side.black,
  ),
  lastMove: HighlightDetails(solidColor: Color(0x80ffff33)),
  selected: HighlightDetails(solidColor: Color(0x80ffff33)),
  validMoves: Color(0x33000000),
  validPremoves: Color(0x40203085),
);
