import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/auth/account.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/section_card.dart";
import "community_providers.dart";

/// Pronostic d'un match (docs/04 J11), en points fictifs : on choisit le vainqueur (3 pts) et,
/// si on veut, le score de série exact (+2 pts) jusqu'au début du match. Chaque choix est
/// enregistré tout de suite (pas de bouton « valider »). Une fois le match commencé, le
/// pronostic est verrouillé ; les points d'un match terminé sont masqués avec le sans spoil.
class PredictionPanel extends ConsumerWidget {
  const PredictionPanel({super.key, required this.event, required this.scoresHidden});

  final EventDetailResponseDto event;
  final bool scoresHidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (event.participants.length != 2) return const SizedBox.shrink();
    final scheduled = event.status == "scheduled";
    final finished = event.status == "finished";
    if (!scheduled && !finished && event.status != "live") return const SizedBox.shrink();
    final prediction = ref.watch(predictionsProvider).value?[event.id];
    // Un match commencé sans pronostic n'a rien à afficher.
    if (!scheduled && prediction == null) return const SizedBox.shrink();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Ton pronostic", style: AppTextStyles.bodyLargeStrong),
          const SizedBox(height: AppSpacing.xs),
          Text(
            scheduled ? "Vainqueur : 3 points. Score exact en plus : +2 points. Jusqu'au début du match." : "Verrouillé : le match a commencé.",
            style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final (i, p) in event.participants.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(child: _TeamChoice(event: event, participant: p, prediction: prediction, enabled: scheduled)),
              ],
            ],
          ),
          if (scheduled && prediction != null) _ScoreChoices(event: event, prediction: prediction),
          if (finished && prediction?.points != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                scoresHidden ? "Points gagnés : •••" : "Points gagnés : ${prediction!.points}",
                style: AppTextStyles.bodyStrong.copyWith(color: scoresHidden || prediction!.points == 0 ? AppColors.textSecondary : AppColors.win),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _save(BuildContext context, WidgetRef ref, String eventId, String entityId, {int? pickedScore, int? otherScore}) async {
  try {
    await ref.read(communityControllerProvider).predict(eventId, entityId, pickedScore: pickedScore, otherScore: otherScore);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e) ?? accountErrorMessage(e))));
  }
}

class _TeamChoice extends ConsumerWidget {
  const _TeamChoice({required this.event, required this.participant, required this.prediction, required this.enabled});

  final EventDetailResponseDto event;
  final EventParticipantDto participant;
  final PredictionDto? prediction;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = prediction?.pickedEntityId == participant.entityId;
    return OutlinedButton(
      onPressed: enabled && !picked ? () => _save(context, ref, event.id, participant.entityId) : null,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: picked ? AppColors.gold : AppColors.surfaceBorderHighlight),
        backgroundColor: picked ? AppColors.gold.withValues(alpha: 0.12) : null,
        disabledForegroundColor: picked ? AppColors.textPrimary : AppColors.textTertiary,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      ),
      child: Text(participant.shortName ?? participant.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Score de série exact, en option : « 2-0 », « 2-1 »… selon le format (BO3 → 2 victoires).
class _ScoreChoices extends ConsumerWidget {
  const _ScoreChoices({required this.event, required this.prediction});

  final EventDetailResponseDto event;
  final PredictionDto prediction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bestOf = event.bestOf?.toInt();
    if (bestOf == null || bestOf < 2) return const SizedBox.shrink();
    final wins = (bestOf + 1) ~/ 2;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          for (var lost = 0; lost < wins; lost++)
            ChoiceChip(
              label: Text("$wins-$lost"),
              selected: prediction.pickedScore?.toInt() == wins && prediction.otherScore?.toInt() == lost,
              onSelected: (_) => _save(context, ref, event.id, prediction.pickedEntityId, pickedScore: wins, otherScore: lost),
            ),
        ],
      ),
    );
  }
}
