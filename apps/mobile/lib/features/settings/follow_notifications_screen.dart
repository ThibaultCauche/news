import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/page_title.dart";
import "../../widgets/section_card.dart";
import "../follows/follows_provider.dart";

/// Ce que chaque suivi déclenche (J21) : rappel 15 minutes avant, début, résultat. Les réglages
/// globaux de l'écran Réglages passent avant : un type coupé là-bas ne part jamais d'ici.
class FollowNotificationsScreen extends ConsumerWidget {
  const FollowNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final follows = ref.watch(followsProvider);
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView(
        value: follows,
        errorMessage: "Impossible de charger tes suivis.",
        onRetry: () => ref.invalidate(followsProvider),
        builder: (all) => _Body(follows: all.where((f) => !f.muted).toList()),
      ),
    );
  }
}

String _kind(String targetType) => switch (targetType) {
  "entity" => "Équipe",
  "event" => "Match",
  "competition" || "competition_family" => "Compétition",
  _ => "Catégorie",
};

class _Body extends ConsumerWidget {
  const _Body({required this.follows});

  final List<FollowStateDto> follows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(followsProvider.notifier);
    Future<void> change(FollowStateDto f, {bool? reminder, bool? start, bool? result}) =>
        runOrShowError(context, () => notifier.setNotifications(f, reminder: reminder, start: start, result: result));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const PageTitle("Notifications par suivi"),
        const SizedBox(height: AppSpacing.xs),
        const Text("Choisis, pour chaque suivi, ce qui te prévient.", style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.lg),
        if (follows.isEmpty) const Text("Tu ne suis rien pour l'instant.", style: TextStyle(color: AppColors.textSecondary)),
        for (final f in follows) ...[
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(_kind(f.targetType).toUpperCase(), style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label, letterSpacing: 1)),
                _Row(label: "Rappel 15 minutes avant", value: f.notifyReminder, onChanged: (v) => change(f, reminder: v)),
                _Row(label: "Début du match", value: f.notifyStart, onChanged: (v) => change(f, start: v)),
                _Row(label: "Résultat", value: f.notifyResult, onChanged: (v) => change(f, result: v)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
