import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../core/offline.dart";
import "../theme/tokens.dart";

/// « Hors ligne · dernière connexion à 10 h 42 » (J18) : le repli sur le cache est silencieux sinon, et on ne
/// saurait pas que ce qu'on voit est ancien. Statique (règle 13), au-dessus de la tab bar.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final since = ref.watch(offlineProvider);
    if (since == null) return const SizedBox.shrink();
    final local = since.toLocal();
    final hour = "${local.hour} h ${local.minute.toString().padLeft(2, "0")}";
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: AppColors.brass.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.brass),
            const SizedBox(width: AppSpacing.sm),
            Flexible(child: Text("Hors ligne · dernière connexion à $hour", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption))),
          ],
        ),
      ),
    );
  }
}
