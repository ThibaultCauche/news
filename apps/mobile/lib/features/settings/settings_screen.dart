import "../forum/forum_providers.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/settings_provider.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/page_title.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../follows/follows_screen.dart";

/// Écran 22 (`docs/02`, J6). Sans spoil et résumé du matin restent globaux
/// (une seule vraie catégorie avec des données pour l'instant : la granularité
/// par catégorie de la maquette attendra une 2e catégorie, `docs/00` §7).
/// Charte de neutralité : texte statique, aucune donnée politique n'existe
/// encore (`docs/03` §7 — "Ensuite").
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setting = ref.watch(userSettingProvider);
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 160,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
          label: const Text("Aujourd'hui", style: TextStyle(color: AppColors.textSecondary)),
        ),
      ),
      body: switch (setting) {
        AsyncData(:final value) => _SettingsBody(setting: value),
        AsyncError() when setting.hasValue => _SettingsBody(setting: setting.value!),
        AsyncError() => const Center(child: Text("Impossible de charger les réglages.")),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.setting});

  final UserSettingDto setting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsControllerProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const PageTitle("Réglages"),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel("SANS SPOIL"),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: _ToggleRow(
            label: "Sans spoil",
            caption: "Scores masqués partout : notifications, agenda, arbre.",
            value: setting.spoilerFree,
            onChanged: (v) => controller.update(spoilerFree: v),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel("NOTIFICATIONS"),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: Column(
            children: [
              _ToggleRow(
                label: "Résumé du matin",
                caption: "L'essentiel en 3 points, 8 h 00.",
                value: setting.morningDigest,
                onChanged: (v) => controller.update(morningDigest: v),
              ),
              if (ref.watch(forumEnabledProvider)) ...[
                const Divider(height: AppSpacing.lg),
                _ToggleRow(
                  label: "Réponses et mentions",
                  caption: "Quand quelqu'un te répond ou te cite avec @pseudo.",
                  value: setting.notifyForumReplies,
                  onChanged: (v) => controller.update(notifyForumReplies: v),
                ),
                const Divider(height: AppSpacing.lg),
                _ToggleRow(
                  label: "Discussions suivies",
                  caption: "Nouveaux messages, au plus un rappel toutes les 10 minutes.",
                  value: setting.notifyForumThreads,
                  onChanged: (v) => controller.update(notifyForumThreads: v),
                ),
              ],
              const Divider(height: AppSpacing.lg),
              _QuietHoursRow(setting: setting, controller: controller),
              const Divider(height: AppSpacing.lg),
              _NavRow(
                label: "Par suivi",
                caption: "Voir et gérer tes suivis",
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FollowsScreen())),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel("AFFICHAGE"),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: Column(
            children: [
              _ToggleRow(
                label: "Tuiles de match compactes",
                caption: "Logo, score, logo — sans le nom des équipes.",
                value: ref.watch(compactEventCardsProvider),
                onChanged: (v) => ref.read(compactEventCardsProvider.notifier).set(v),
              ),
              const Divider(height: AppSpacing.lg),
              const _StaticRow(label: "Mouvement réduit", caption: "Comme l'iPhone : suit le réglage du système."),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel("SOURCES ET CRÉDITS"),
        const SizedBox(height: AppSpacing.sm),
        const SectionCard(
          child: Column(
            children: [
              _StaticRow(label: "E-sport", caption: "Données PandaScore"),
              Divider(height: AppSpacing.lg),
              _StaticRow(label: "Contexte des compétitions", caption: "Liquipedia, licence CC-BY-SA"),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel("CHARTE DE NEUTRALITÉ"),
        const SizedBox(height: AppSpacing.sm),
        const SectionCard(
          child: Text(
            "Les catégories qui touchent à la vie publique (politique, élections) s'appuient uniquement sur des "
            "données officielles, avec les noms officiels des groupes et des phrases écrites à l'avance, jamais "
            "générées librement. La source est toujours indiquée.",
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.caption, required this.value, required this.onChanged});

  final String label;
  final String caption;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.bodyLargeStrong),
              Text(caption, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _StaticRow extends StatelessWidget {
  const _StaticRow({required this.label, required this.caption});

  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.bodyLargeStrong),
              Text(caption, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.label, required this.caption, required this.onTap});

  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.bodyLargeStrong),
                Text(caption, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

/// `null` (pas d'heures calmes) affiché comme un troisième choix "Aucune" — le
/// client généré ne peut pas envoyer de `null` explicite pour les effacer
/// (limite d'`openapi-generator` dart-dio sur les champs optionnels nullables),
/// donc seul le réglage d'une plage complète est proposé ici.
class _QuietHoursRow extends StatelessWidget {
  const _QuietHoursRow({required this.setting, required this.controller});

  final UserSettingDto setting;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final hours = List.generate(24, (h) => h);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Heures calmes", style: AppTextStyles.bodyLargeStrong),
              const Text("Seulement ton équipe en direct", style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
            ],
          ),
        ),
        DropdownButton<int>(
          value: setting.quietHoursStart?.toInt(),
          hint: const Text("—"),
          items: [for (final h in hours) DropdownMenuItem(value: h, child: Text("${h}h"))],
          onChanged: (v) => v != null ? controller.update(quietHoursStart: v) : null,
        ),
        const Text(" – "),
        DropdownButton<int>(
          value: setting.quietHoursEnd?.toInt(),
          hint: const Text("—"),
          items: [for (final h in hours) DropdownMenuItem(value: h, child: Text("${h}h"))],
          onChanged: (v) => v != null ? controller.update(quietHoursEnd: v) : null,
        ),
      ],
    );
  }
}
