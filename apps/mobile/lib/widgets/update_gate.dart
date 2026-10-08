import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:url_launcher/url_launcher.dart";
import "../core/app_update.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";

const _whatsNewKey = "whatsNew.seenVersion";

/// Vérification de version au lancement (J21) : un bandeau qu'on peut fermer sous `latest`, un écran
/// qui bloque tout sous `minSupported`. Statique (règle 13).
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key});

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  bool _dismissed = false;
  bool _whatsNewChecked = false;

  // Web : « mettre à jour » = recharger la page, qui charge la dernière version servie par l'API.
  void _open() => kIsWeb ? launchUrl(Uri.base, webOnlyWindowName: "_self") : launchUrl(storeUri, mode: LaunchMode.externalApplication);

  /// « Quoi de neuf » (J17) : les notes de la version à jour, une seule fois par version. La toute première
  /// ouverture ne montre rien : on enregistre seulement la version.
  Future<void> _maybeShowWhatsNew(AppUpdate update) async {
    final version = update.version, notes = update.notes;
    if (_whatsNewChecked || version == null || update.level != UpdateLevel.none) return;
    _whatsNewChecked = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getString(_whatsNewKey);
      if (seen == version) return;
      await prefs.setString(_whatsNewKey, version);
      if (seen == null || notes == null || !mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Quoi de neuf", style: AppTextStyles.sectionTitle),
                const SizedBox(height: AppSpacing.sm),
                Text(notes, style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(appUpdateProvider).value;
    if (update == null) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWhatsNew(update));
    final notes = update.notes;
    final message = update.message;
    if (update.level == UpdateLevel.none) {
      return message == null || _dismissed ? const SizedBox.shrink() : _banner(message, withUpdate: false);
    }

    if (update.level == UpdateLevel.required) {
      return Positioned.fill(
        child: Material(
          color: AppColors.background,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.system_update_rounded, size: 48, color: AppColors.brass),
                  const SizedBox(height: AppSpacing.md),
                  Text("Mise à jour nécessaire", textAlign: TextAlign.center, style: AppTextStyles.pageTitle),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "Cette version de Keryx n'est plus prise en charge.${notes == null ? "" : "\n$notes"}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(onPressed: _open, child: const Text("Mettre à jour")),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_dismissed) return const SizedBox.shrink();
    return _banner(message ?? notes ?? "Une mise à jour de Keryx est disponible.", withUpdate: true);
  }

  Widget _banner(String text, {required bool withUpdate}) {
    return Positioned(
      left: AppSpacing.md,
      right: AppSpacing.md,
      top: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Container(
            padding: const EdgeInsets.only(left: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.brass.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(text, style: const TextStyle(fontSize: AppTypography.caption))),
                if (withUpdate) TextButton(onPressed: _open, child: const Text("Mettre à jour")),
                IconButton(icon: const Icon(Icons.close_rounded, size: 18), tooltip: "Fermer", onPressed: () => setState(() => _dismissed = true)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
