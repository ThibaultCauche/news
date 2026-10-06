import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../core/auth/account.dart";
import "../core/notifications/local_notifications.dart";
import "../theme/tokens.dart";
import "ornate_frame.dart";

/// Les notifications sont-elles autorisées pour l'appli ? Revérifié quand on revient dans l'appli (après un tour dans
/// les réglages du téléphone).
final notificationsEnabledProvider = FutureProvider.autoDispose<bool>((ref) => areNotificationsEnabled());

/// Bandeau « les notifications sont désactivées » (J22) : sans la permission Android, aucune alerte n'arrive et rien
/// ne le dit. Visible seulement pour un compte connecté (lui seul peut suivre) quand elles sont coupées ; rien sinon.
/// « Autoriser » redemande la permission ; si Android ne la repose plus, le bandeau dit où la réactiver.
class NotificationsDisabledBanner extends ConsumerStatefulWidget {
  const NotificationsDisabledBanner({super.key, this.margin = const EdgeInsets.only(bottom: AppSpacing.sm)});

  final EdgeInsetsGeometry margin;

  @override
  ConsumerState<NotificationsDisabledBanner> createState() => _NotificationsDisabledBannerState();
}

class _NotificationsDisabledBannerState extends ConsumerState<NotificationsDisabledBanner> with WidgetsBindingObserver {
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(notificationsEnabledProvider);
  }

  Future<void> _allow() async {
    await requestNotificationPermission();
    ref.invalidate(notificationsEnabledProvider);
    if (mounted) setState(() => _asked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(signedInProvider)) return const SizedBox.shrink();
    final enabled = ref.watch(notificationsEnabledProvider).value ?? true;
    if (enabled) return const SizedBox.shrink();
    return Padding(
      padding: widget.margin,
      child: OrnateFrame(
        color: AppColors.live,
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppColors.live.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadii.card)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.notifications_off_rounded, color: AppColors.live),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Notifications désactivées", style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        _asked
                            ? "Active-les dans Réglages Android → Applications → Keryx → Notifications."
                            : "Tu ne recevras aucune alerte de tes suivis tant qu'elles sont coupées.",
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
                      ),
                    ],
                  ),
                ),
                if (!_asked) TextButton(onPressed: _allow, child: const Text("Autoriser")),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
