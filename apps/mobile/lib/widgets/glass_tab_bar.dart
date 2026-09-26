import "dart:ui";

import "package:flutter/material.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";

class GlassTabBarItem {
  const GlassTabBarItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
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
  static const _pillWidth = 86.0;
  static const _pillHeight = 50.0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
        child: ClipRRect(
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
                  final slotWidth = constraints.maxWidth / items.length;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: AppMotion.enterDuration,
                        curve: AppMotion.enter,
                        left: currentIndex * slotWidth + (slotWidth - _pillWidth) / 2,
                        top: (_barHeight - _pillHeight) / 2,
                        width: _pillWidth,
                        height: _pillHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(_pillHeight / 2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (final (index, item) in items.indexed)
                            Expanded(
                              child: _TabButton(item: item, selected: index == currentIndex, onTap: () => onTap(index)),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.item, required this.selected, required this.onTap});

  final GlassTabBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(item.label, style: (selected ? AppTextStyles.tabLabelActive : AppTextStyles.tabLabel).copyWith(color: color)),
        ],
      ),
    );
  }
}
