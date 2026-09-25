import "dart:ui";

import "package:flutter/material.dart";
import "../theme/tokens.dart";

class GlassTabBarItem {
  const GlassTabBarItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Tab bar V2 : capsule de verre flottante (`docs/02` — flou 24, `#1C1C21`
/// à 72–94 %), au lieu du `BottomNavigationBar` opaque de Material.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({super.key, required this.items, required this.currentIndex, required this.onTap});

  final List<GlassTabBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

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
              decoration: BoxDecoration(
                color: AppColors.glass.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final (index, item) in items.indexed)
                    _TabButton(item: item, selected: index == currentIndex, onTap: () => onTap(index)),
                ],
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
    final color = selected ? AppColors.textPrimary : AppColors.textTertiary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(item.label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
