import "package:flutter/material.dart";
import "../theme/tokens.dart";
import "glass_tab_bar.dart";

/// Navigation latérale du mode ordinateur (J17) : mêmes destinations que la tab bar, en colonne à gauche.
class SideRail extends StatelessWidget {
  const SideRail({super.key, required this.items, required this.currentIndex, required this.onTap});

  final List<GlassTabBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),
            for (var i = 0; i < items.length; i++) _RailItem(item: items[i], selected: i == currentIndex, onTap: () => onTap(i)),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.item, required this.selected, required this.onTap});

  final GlassTabBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.brass : AppColors.textSecondary;
    Widget icon = Icon(item.icon, color: item.featured ? AppColors.background : color, size: 24);
    if (item.featured) {
      icon = Container(width: 44, height: 44, decoration: const BoxDecoration(color: AppColors.brass, shape: BoxShape.circle), child: icon);
    }
    if (item.badge > 0) icon = Badge(label: Text("${item.badge}"), child: icon);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          width: 96,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.brass.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 4),
              Text(item.label, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
