import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/date_x.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/event_card.dart";
import "../../widgets/match_visuals.dart";
import "../../widgets/section_label.dart";
import "../follows/follows_provider.dart";
import "../next_match/next_match_screen.dart";

/// « Grands rendez-vous » de l'Accueil (docs/04 J10) : la grande finale d'une phase
/// finale, un gros moment et souvent le point d'entrée d'un néophyte — d'où une
/// carte à part d'`EventCard`, avec la phrase « pourquoi ça compte » (`stakes`,
/// mots `[[terme]]` ouvrant le glossaire) et l'alerte en toutes lettres.
class GrandFinalCard extends ConsumerWidget {
  const GrandFinalCard({super.key, required this.grandFinal});

  final GrandFinalDto grandFinal;

  String get _dateLabel {
    final start = grandFinal.event.startsAt.toDateTime?.toLocal();
    if (start == null) return "Date à confirmer";
    final text = DateFormat("EEEE d MMMM · HH'h'mm", "fr_FR").format(start);
    return text[0].toUpperCase() + text.substring(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = grandFinal.event;
    final textTheme = Theme.of(context).textTheme;
    final teams = event.participants.toList();
    final hasTwoTeams = teams.length == 2;

    Color? accentOf(EventParticipantDto p) {
      final url = p.imageUrl;
      return url == null ? null : ref.watch(entityAccentColorProvider(url)).value;
    }

    final colorA = hasTwoTeams ? accentOf(teams[0]) : null;
    final colorB = hasTwoTeams ? accentOf(teams[1]) : null;
    final active = isFollowing(ref.watch(followsProvider).value, FollowTargetType.event, event.id);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.surfaceBorder),
        gradient: teamsGradient(colorA, colorB),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: Text(grandFinal.tournamentName, style: textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                    const SectionLabel("GRANDE FINALE"),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(child: Text(_dateLabel, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                const SizedBox(height: AppSpacing.md),
                if (hasTwoTeams)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _FinalTeam(participant: teams[0]),
                      const Text(
                        "VS",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, fontSize: 22),
                      ),
                      _FinalTeam(participant: teams[1]),
                    ],
                  )
                else
                  Center(child: Text("Adversaires à déterminer", style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary))),
                if (grandFinal.stakes != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  const SectionLabel("POURQUOI ÇA COMPTE"),
                  const SizedBox(height: AppSpacing.xs),
                  StakesText(text: grandFinal.stakes!),
                ],
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: active ? AppColors.gold.withValues(alpha: 0.14) : AppColors.textPrimary,
                      foregroundColor: active ? AppColors.gold : AppColors.background,
                    ),
                    icon: Icon(active ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, size: 18),
                    label: Text(active ? "Alerte activée" : "M'alerter au début du match"),
                    onPressed: () => toggleEventAlert(context, ref, event.id, active: active),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FinalTeam extends StatelessWidget {
  const _FinalTeam({required this.participant});

  final EventParticipantDto participant;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamBadge(imageUrl: participant.imageUrl, diameter: 56),
        const SizedBox(height: AppSpacing.xs),
        Text(participant.shortName ?? participant.name, style: AppTextStyles.bodyLargeStrong),
      ],
    );
  }
}
