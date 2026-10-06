import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:url_launcher/url_launcher.dart";
import "../core/app_update.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";

/// Vérification de version au lancement (J21) : un bandeau qu'on peut fermer sous `latest`, un écran
/// qui bloque tout sous `minSupported`. Statique (règle 13).
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key});

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  bool _dismissed = false;

  void _open() => launchUrl(storeUri, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(appUpdateProvider).value;
    if (update == null || update.level == UpdateLevel.none) return const SizedBox.shrink();
    final notes = update.notes;

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
                Expanded(child: Text(notes ?? "Une mise à jour de Keryx est disponible.", style: const TextStyle(fontSize: AppTypography.caption))),
                TextButton(onPressed: _open, child: const Text("Mettre à jour")),
                IconButton(icon: const Icon(Icons.close_rounded, size: 18), tooltip: "Fermer", onPressed: () => setState(() => _dismissed = true)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
