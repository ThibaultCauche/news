import "dart:ui";

import "package:flutter/material.dart";

import "../theme/app_theme.dart";
import "../theme/tokens.dart";

class GlassTabBarItem {
  const GlassTabBarItem({required this.icon, required this.label, this.featured = false});

  final IconData icon;
  final String label;

  /// Onglet mis en avant (Compétitions, J9) : icône dans un cercle or qui dépasse
  /// de la barre (or = « à moi », comme Suivis, `docs/02`).
  final bool featured;
}

/// Tab bar V2 : capsule de verre flottante (`docs/maquettes/specs/tab-bar.md`
/// — 64 de haut, flou 24, `#1C1C21` à 72 %, contour blanc 12 %, pastille de
/// l'onglet actif 86×50 blanc 12 %), au lieu du `BottomNavigationBar` opaque
/// de Material.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({super.key, required this.items, required this.currentIndex, required this.onTap});

  final List<GlassTabBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _barHeight = 64.0;
  static const _pillHeight = 50.0;
  // Piste des onglets mesurée sur la maquette (358 de large, 4 onglets) :
  // les pastilles sont **contiguës** (86 de large chacune, aucun espace
  // entre elles) et seule la piste entière est centrée dans la barre avec
  // une marge de 7 de chaque côté (`docs/maquettes/specs/tab-bar.md`). Le
  // ratio 7/358 reste correct quelle que soit la largeur d'écran.
  static const _trackMarginRatio = 7 / 358;

  static const _featuredSize = 54.0;
  // Dépassement au-dessus de la barre, hors du `ClipRRect` (sinon rogné).
  static const _featuredRise = 22.0;

  @override
  Widget build(BuildContext context) {
    final featuredIndex = items.indexWhere((i) => i.featured);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _bar(),
            if (featuredIndex >= 0)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final trackMargin = constraints.maxWidth * _trackMarginRatio;
                    final slotWidth = (constraints.maxWidth - 2 * trackMargin) / items.length;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: trackMargin + featuredIndex * slotWidth + (slotWidth - _featuredSize) / 2,
                          top: -_featuredRise,
                          child: GestureDetector(
                            onTap: () => onTap(featuredIndex),
                            child: Container(
                              width: _featuredSize,
                              height: _featuredSize,
                              decoration: BoxDecoration(
                                color: AppColors.gold,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.background, width: 3),
                              ),
                              child: Icon(items[featuredIndex].icon, color: AppColors.background, size: 26),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: _barHeight,
          decoration: BoxDecoration(
            color: AppColors.glass.withValues(alpha: AppColors.glassOpacity),
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackMargin = constraints.maxWidth * _trackMarginRatio;
              final slotWidth = (constraints.maxWidth - 2 * trackMargin) / items.length;
              return Stack(
                // La Row (icône+texte) ne fait que sa hauteur de contenu (~38) : sans
                // ce centrage, un Stack aligne ses enfants non positionnés en haut.
                alignment: Alignment.center,
                children: [
                  if (currentIndex != featuredIndexOf(items))
                    AnimatedPositioned(
                      duration: AppMotion.enterDuration,
                      curve: AppMotion.enter,
                      left: trackMargin + currentIndex * slotWidth,
                      top: (_barHeight - _pillHeight) / 2,
                      width: slotWidth,
                      height: _pillHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(_pillHeight / 2),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: trackMargin),
                    child: Row(
                      children: [
                        for (final (index, item) in items.indexed)
                          Expanded(
                            child: _TabButton(item: item, selected: index == currentIndex, onTap: () => onTap(index)),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

int featuredIndexOf(List<GlassTabBarItem> items) => items.indexWhere((i) => i.featured);

class _TabButton extends StatelessWidget {
  const _TabButton({required this.item, required this.selected, required this.onTap});

  final GlassTabBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = item.featured
        ? (selected ? AppColors.gold : AppColors.textSecondary)
        : (selected ? AppColors.textPrimary : AppColors.textSecondary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // L'icône de l'onglet mis en avant est dessinée par le cercle or, au-dessus.
          if (item.featured) const SizedBox(height: 20) else Icon(item.icon, color: color, size: 20),
          const SizedBox(height: 6),
          // Rétrécit plutôt que de passer à la ligne (« Compétition/s » sur un écran de 360 dp).
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(item.label, maxLines: 1, style: (selected ? AppTextStyles.tabLabelActive : AppTextStyles.tabLabel).copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
