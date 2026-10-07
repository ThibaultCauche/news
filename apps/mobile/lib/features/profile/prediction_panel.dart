import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/avatar_circle.dart";
import "../../widgets/section_card.dart";
import "../discussion/share_sheet.dart";
import "community_providers.dart";
import "player_profile_screen.dart";

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
    // Le choix en cours d'envoi s'affiche tout de suite, sans attendre le serveur.
    final pending = ref.watch(pendingPicksProvider)[event.id];
    final pickedEntityId = pending?.entityId ?? prediction?.pickedEntityId;
    final pickedScore = pending != null ? pending.picked : prediction?.pickedScore?.toInt();
    final otherScore = pending != null ? pending.other : prediction?.otherScore?.toInt();
    // Un match commencé sans pronostic n'a que les choix des amis à afficher.
    if (!scheduled && prediction == null) return _FriendsPicks(event: event, first: true);

    return Column(
      children: [
        SectionCard(
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
                Expanded(child: _TeamChoice(event: event, participant: p, pickedEntityId: pickedEntityId, enabled: scheduled)),
              ],
            ],
          ),
          if (scheduled && pickedEntityId != null) _ScoreChoices(event: event, pickedEntityId: pickedEntityId, pickedScore: pickedScore, otherScore: otherScore),
          if (prediction != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () => showShareSheet(context, ref, kind: ShareDtoKindEnum.prediction, refId: event.id),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text("Partager mon pronostic"),
              ),
            ),
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
        ),
        if (!scheduled) _FriendsPicks(event: event, first: false),
      ],
    );
  }
}

/// « 3 amis sur 5 ont choisi G2 » (J14) : seulement une fois le match commencé, et seulement les
/// membres de tes groupes. Le serveur ne renvoie rien avant le coup d'envoi.
class _FriendsPicks extends ConsumerWidget {
  const _FriendsPicks({required this.event, required this.first});

  final EventDetailResponseDto event;
  // Seul bloc du panneau (pas de pronostic au-dessus) : pas de marge en haut.
  final bool first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(friendsPicksProvider(event.id)).value ?? const <FriendPickDto>[];
    if (picks.isEmpty) return const SizedBox.shrink();
    String teamName(String entityId) {
      final team = event.participants.where((p) => p.entityId == entityId).firstOrNull;
      return team == null ? "?" : (team.shortName ?? team.name);
    }

    final counts = <String, int>{};
    for (final pick in picks) {
      counts.update(pick.pickedEntityId, (n) => n + 1, ifAbsent: () => 1);
    }
    // Un seul ami : « Ton ami a choisi G2 » ; sinon « 2 sur 3 ont choisi G2 · 1 sur 3 a choisi PRX ».
    final summary = picks.length == 1
        ? "Ton ami a choisi ${teamName(picks.first.pickedEntityId)}"
        : counts.entries.map((e) => "${e.value} sur ${picks.length} ${e.value > 1 ? "ont" : "a"} choisi ${teamName(e.key)}").join(" · ");
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : AppSpacing.md),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Choix de tes amis", style: AppTextStyles.bodyLargeStrong),
            Text(summary, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
            const SizedBox(height: AppSpacing.sm),
            for (final pick in picks)
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfileScreen(userId: pick.userId))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      AvatarCircle(avatarUrl: pick.avatarUrl, pseudo: pick.pseudo, radius: 14),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(pick.pseudo, style: AppTextStyles.bodyStrong)),
                      Text(
                        pick.pickedScore != null && pick.otherScore != null ? "${teamName(pick.pickedEntityId)} ${pick.pickedScore}-${pick.otherScore}" : teamName(pick.pickedEntityId),
                        style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Un envoi à la fois par match, mais le dernier choix n'est jamais perdu (J19) : le serveur peut mettre 5 s à
// répondre, et un nouvel appui pendant ce temps s'affiche aussitôt puis part dès que l'envoi en cours est fini.
final _saving = <String>{};
final _queued = <String, PendingPick>{};

Future<void> _save(BuildContext context, WidgetRef ref, String eventId, String entityId, {int? pickedScore, int? otherScore}) async {
  final pick = (entityId: entityId, picked: pickedScore, other: otherScore);
  final pending = ref.read(pendingPicksProvider.notifier);
  pending.set(eventId, pick);
  if (!_saving.add(eventId)) {
    _queued[eventId] = pick;
    return;
  }
  try {
    PendingPick? current = pick;
    while (current != null) {
      await ref.read(communityControllerProvider).predict(eventId, current.entityId, pickedScore: current.picked, otherScore: current.other);
      current = _queued.remove(eventId);
    }
  } catch (e) {
    _queued.remove(eventId);
    if (context.mounted) showErrorSnackBar(context, e);
  } finally {
    pending.set(eventId, null);
    _saving.remove(eventId);
  }
}

class _TeamChoice extends ConsumerWidget {
  const _TeamChoice({required this.event, required this.participant, required this.pickedEntityId, required this.enabled});

  final EventDetailResponseDto event;
  final EventParticipantDto participant;
  final String? pickedEntityId;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = pickedEntityId == participant.entityId;
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
  const _ScoreChoices({required this.event, required this.pickedEntityId, required this.pickedScore, required this.otherScore});

  final EventDetailResponseDto event;
  final String pickedEntityId;
  final int? pickedScore;
  final int? otherScore;

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
              selected: pickedScore == wins && otherScore == lost,
              onSelected: (_) => _save(context, ref, event.id, pickedEntityId, pickedScore: wins, otherScore: lost),
            ),
        ],
      ),
    );
  }
}
