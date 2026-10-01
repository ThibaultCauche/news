import "package:flutter/material.dart";
import "../theme/tokens.dart";
import "ornate_frame.dart";

/// Carte de section (`docs/maquettes/specs/commun.md`) : surface `#16171B`,
/// rayon 22 (`AppRadii.card`), contour blanc 8 % (10 % si [highlight], pour
/// les cartes à dégradé / mises en avant), reflet intérieur blanc 7 % en
/// haut (mesuré : décalage 1 px, flou 0 — un simple filet, pas un flou).
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.highlight = false, this.padding = const EdgeInsets.all(AppSpacing.md)});

  final Widget child;
  final bool highlight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(AppRadii.card);
    return OrnateFrame(
      child: Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: borderRadius),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            const Positioned(top: 1, left: 0, right: 0, child: ColoredBox(color: AppColors.surfaceHighlight, child: SizedBox(height: 1))),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    ),
    );
  }
}
