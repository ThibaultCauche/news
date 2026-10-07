import "package:flutter/material.dart";
import "package:news_api_client/news_api_client.dart";
import "../features/bracket/bracket_model.dart";
import "../theme/tokens.dart";
import "bracket_match_card.dart";

const _gapX = 28.0;
const _rowStride = bracketCardHeight + 16;

/// Pyramide à l'horizontale (J20) : les premiers tours à gauche, le match décisif à droite. Au
/// premier affichage, **elle se place d'elle-même sur le prochain match** (en direct, sinon le
/// prochain d'une équipe suivie, sinon le prochain à jouer), dont la case porte un cadre renforcé.
/// Seul le chemin des gagnants est tracé.
///
/// Deux façons de la parcourir : [pannable] (phase finale) se déplace dans tous les sens, en
/// diagonale, et se pince pour zoomer ; sinon elle défile seulement à l'horizontale (les poules,
/// qui ne sont pas plus hautes que l'écran).
///
/// [layout] et [links] remplacent le placement et les traits calculés depuis `bracket` : une poule
/// à 5 matchs a une forme fixe, et PandaScore n'y donne pas toujours tous les liens (J19).
/// [trailing] : une case posée à droite du dernier tour (les « Qualifiés »), reliée par les matchs
/// de [trailingFrom].
class HorizontalBracket extends StatefulWidget {
  const HorizontalBracket({
    super.key,
    required this.bracket,
    this.followed = const {},
    this.pannable = false,
    this.layout,
    this.links,
    this.trailing,
    this.trailingFrom = const [],
  });

  final BracketResponseDto bracket;
  final Set<String> followed;
  final bool pannable;
  final GridLayout? layout;
  final List<(String, String)>? links;
  final Widget? trailing;
  final List<String> trailingFrom;

  @override
  State<HorizontalBracket> createState() => _HorizontalBracketState();
}

class _HorizontalBracketState extends State<HorizontalBracket> {
  final _scroll = ScrollController();
  final _transform = TransformationController();
  bool _centered = false;
  // Fenêtre pour laquelle la vue a été calée, et geste de la personne : tant qu'elle n'a pas touché au dessin, on
  // recale si la fenêtre change (le premier calcul peut tomber sur une hauteur provisoire, d'où un écran vide).
  Size? _centeredFor;
  bool _interacted = false;

  @override
  void dispose() {
    _scroll.dispose();
    _transform.dispose();
    super.dispose();
  }

  /// Une seule fois : si le prochain match change pendant que l'écran est ouvert, on ne
  /// déplace pas la vue sous les doigts de la personne.
  void _centerHorizontally(double left) {
    if (_centered) return;
    _centered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      _scroll.jumpTo((left - (position.viewportDimension - bracketCardWidth) / 2).clamp(0.0, position.maxScrollExtent));
    });
  }

  void _centerBoth(Size viewport, Size content, Offset topLeft) {
    if (_interacted || (_centered && _centeredFor == viewport)) return;
    _centered = true;
    _centeredFor = viewport;
    double fit(double target, double view, double size) => size <= view ? 0 : (-(target - (view - 0) / 2)).clamp(view - size, 0.0);
    _transform.value = Matrix4.translationValues(
      fit(topLeft.dx + bracketCardWidth / 2, viewport.width, content.width),
      fit(topLeft.dy + bracketCardHeight / 2, viewport.height, content.height),
      0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bracket = widget.bracket;
    final layout = widget.layout ?? buildGridLayout(bracket);
    final byId = {for (final n in bracket.nodes) n.eventId: n};
    final incoming = <String, List<BracketLinkDto>>{};
    for (final l in bracket.links) {
      incoming.putIfAbsent(l.toEventId, () => []).add(l);
    }
    final nextId = nextMatchId(bracket, widget.followed);

    double leftOf(int col) => col * (bracketCardWidth + _gapX);
    double topOf(double row) => row * _rowStride;
    final columns = layout.cols + (widget.trailing != null ? 1 : 0);
    final width = columns * (bracketCardWidth + _gapX) - _gapX;
    final height = (layout.rows - 1) * _rowStride + bracketCardHeight;

    final fromRows = [for (final id in widget.trailingFrom) layout.cell(id)?.row].whereType<double>().toList();
    final trailingRow = fromRows.isEmpty ? 0.0 : fromRows.reduce((a, b) => a + b) / fromRows.length;
    final anchorId = anchorMatchId(bracket, widget.followed);
    final next = anchorId == null ? null : layout.cell(anchorId);
    final nextTopLeft = next == null ? Offset.zero : Offset(leftOf(next.col), topOf(next.row));

    final content = SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          CustomPaint(
            size: Size(width, height),
            painter: _LinksPainter(
              layout: layout,
              links: widget.links ?? [for (final l in bracket.links) if (l.outcome == "winner") (l.fromEventId, l.toEventId)],
              trailingFrom: widget.trailing == null ? const [] : widget.trailingFrom,
              trailingLeft: leftOf(layout.cols),
              trailingTop: topOf(trailingRow) + bracketCardHeight / 2,
            ),
          ),
          for (final cell in layout.cells)
            Positioned(
              left: leftOf(cell.col),
              top: topOf(cell.row),
              child: BracketMatchCard(
                node: cell.node,
                sides: matchSides(cell.node, incoming[cell.node.eventId] ?? const [], byId),
                followed: widget.followed,
                emphasis: cell.node.status == "live" ? CardEmphasis.live : (cell.node.eventId == nextId ? CardEmphasis.next : CardEmphasis.none),
              ),
            ),
          if (widget.trailing != null)
            Positioned(left: leftOf(layout.cols), top: topOf(trailingRow), width: bracketCardWidth, height: bracketCardHeight, child: widget.trailing!),
        ],
      ),
    );

    if (!widget.pannable) {
      _centerHorizontally(nextTopLeft.dx);
      return SingleChildScrollView(controller: _scroll, scrollDirection: Axis.horizontal, child: content);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _centerBoth(Size(constraints.maxWidth, constraints.maxHeight), Size(width, height), nextTopLeft);
        return InteractiveViewer(
          transformationController: _transform,
          onInteractionStart: (_) => _interacted = true,
          constrained: false,
          minScale: 0.5,
          maxScale: 1.6,
          boundaryMargin: const EdgeInsets.all(48),
          child: content,
        );
      },
    );
  }
}

/// Traits en coude, uniquement vers l'endroit où va le **gagnant** : le perdant d'un match n'est
/// pas tracé (sa prochaine case le dit en toutes lettres, « Perdant de la demi-finale 1 »).
class _LinksPainter extends CustomPainter {
  _LinksPainter({required this.layout, required this.links, required this.trailingFrom, required this.trailingLeft, required this.trailingTop});

  final GridLayout layout;
  final List<(String, String)> links;
  final List<String> trailingFrom;
  final double trailingLeft;
  final double trailingTop;

  Offset _out(GridCell c) => Offset(c.col * (bracketCardWidth + _gapX) + bracketCardWidth, c.row * _rowStride + bracketCardHeight / 2);
  Offset _in(GridCell c) => Offset(c.col * (bracketCardWidth + _gapX), c.row * _rowStride + bracketCardHeight / 2);

  void _elbow(Canvas canvas, Paint paint, Offset from, Offset to) {
    final midX = from.dx + (to.dx - from.dx) / 2;
    canvas.drawPath(
      Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(midX, from.dy)
        ..lineTo(midX, to.dy)
        ..lineTo(to.dx, to.dy),
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.brass.withValues(alpha: 0.6);
    for (final (fromId, toId) in links) {
      final from = layout.cell(fromId);
      final to = layout.cell(toId);
      if (from != null && to != null) _elbow(canvas, paint, _out(from), _in(to));
    }
    for (final id in trailingFrom) {
      final from = layout.cell(id);
      if (from != null) _elbow(canvas, paint, _out(from), Offset(trailingLeft, trailingTop));
    }
  }

  @override
  bool shouldRepaint(covariant _LinksPainter oldDelegate) => oldDelegate.links != links || oldDelegate.layout != layout;
}
