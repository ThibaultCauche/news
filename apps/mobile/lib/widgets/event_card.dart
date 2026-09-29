import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "package:palette_generator/palette_generator.dart";
import "../core/date_x.dart";
import "../core/settings_provider.dart";
import "../domain/event_status.dart";
import "../theme/app_theme.dart";
import "../features/follows/follows_provider.dart";
import "../theme/tokens.dart";
import "live_dot.dart";
import "match_countdown.dart";
import "match_visuals.dart";

/// Couleur dominante d'un logo d'équipe, mise en cache par URL (un seul calcul
/// par équipe même si sa tuile apparaît sur plusieurs écrans) : teinte le fond
/// de la tuile de match (`EventCard`), pas de champ couleur en base (le
/// modèle reste générique, règle 3 de CLAUDE.md).
final entityAccentColorProvider = FutureProvider.family<Color?, String>((ref, imageUrl) async {
  try {
    final palette = await PaletteGenerator.fromImageProvider(NetworkImage(imageUrl), maximumColorCount: 8);
    return palette.vibrantColor?.color ?? palette.dominantColor?.color;
  } catch (_) {
    return null;
  }
});

/// Tuile de match réutilisée par l'agenda, la saison, l'accueil, les suivis et
/// la fiche équipe — heure à gauche, score/statut à droite, comme l'écran 09
/// des maquettes (`docs/02`) : mêmes règles d'affichage quel que soit l'écran
/// (règle 12 — la couleur porte toujours le même sens). Sans spoil (écran 15,
/// J6) : [scoresHidden] masque le score d'un match terminé, lu une seule fois
/// par l'écran appelant (`userSettingProvider`) plutôt que par chaque carte —
/// pas d'appui long ici, seulement sur l'écran du match (`NextMatchScreen`).
class EventCard extends ConsumerWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.scoresHidden,
    this.onTap,
    this.followedEntityIds = const {},
    this.showCountdown = false,
  });

  /// Compte à rebours en gros à la place du "VS" (bannière "À suivre" de l'Accueil,
  /// J10) : un match à venir seulement, sinon le "VS" habituel.
  final bool showCountdown;

  /// Score d'un match terminé masqué (réglage sans spoil du compte).
  final bool scoresHidden;

  final EventSummaryDto event;
  final VoidCallback? onTap;

  /// `entityId` des équipes/joueurs suivis : affichés en or
  /// (`docs/maquettes/specs/01-valorant-saison.md`, `06-groupes.md`), comme
  /// `highlightedEventIds` dans `bracket_screen.dart`.
  final Set<String> followedEntityIds;

  // Un match à venir, mais seulement s'il tombe demain (le "quand" qu'on
  // retient le moins bien) : pas un décompte qui tourne (`_Countdown` de
  // l'écran Prochain match, à la seconde) — beaucoup trop lourd à multiplier
  // sur toute une liste — juste un texte statique, recalculé au prochain
  // rebuild naturel de la tuile.
  Widget? _tomorrowCountdown(EventStatusKind status, DateTime startsAt, TextTheme textTheme) {
    if (status != EventStatusKind.scheduled) return null;
    final now = DateTime.now();
    final startDay = DateTime(startsAt.year, startsAt.month, startsAt.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (startDay != tomorrow) return null;
    final remaining = startsAt.difference(now);
    if (remaining.isNegative) return null;
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text("· dans ${h}h${m.toString().padLeft(2, "0")}", style: textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
    );
  }

  String? get _scoreLine {
    if (event.participants.length != 2) return null;
    final a = event.participants[0].score;
    final b = event.participants[1].score;
    if (a == null || b == null) return null;
    return "$a-$b";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = event.status.statusKind;
    final textTheme = Theme.of(context).textTheme;
    // Un match à venir n'a pas de score : l'API renvoie 0-0, à ne pas afficher.
    final score = status == EventStatusKind.scheduled || (status == EventStatusKind.finished && scoresHidden) ? null : _scoreLine;
    final hasTwoTeams = event.participants.length == 2;
    final teamA = hasTwoTeams ? event.participants[0] : null;
    final teamB = hasTwoTeams ? event.participants[1] : null;

    Color? accentOf(EventParticipantDto? p) {
      final url = p?.imageUrl;
      if (url == null) return null;
      return ref.watch(entityAccentColorProvider(url)).value;
    }

    final colorA = accentOf(teamA);
    final colorB = accentOf(teamB);

    // Repère central entre les deux logos : "VS" tout le temps (pas
    // seulement avant le match), sauf reporté où le statut prime. Fonction
    // plutôt qu'un widget figé : la tuile réduite le veut plus petit, au
    // même niveau visuel que ses logos et scores plus petits eux aussi.
    final countdownTarget = showCountdown && status == EventStatusKind.scheduled ? event.startsAt.toDateTime : null;
    Widget centerBadge(double fontSize) => status == EventStatusKind.postponed
        ? Text(status.label, style: textTheme.bodySmall?.copyWith(color: status.color))
        : countdownTarget != null
        ? MatchCountdown(startsAt: countdownTarget, fontSize: fontSize)
        : Text(
            "VS",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, fontSize: fontSize),
          );

    // BOx redevient utile en l'absence de score (personne à départager encore) ;
    // une fois le score affiché, il fait doublon avec "le format BO3".
    final subtitle = [event.competition.name, if (score == null && event.bestOf != null) "BO${event.bestOf}"].join(" · ");

    // En haut, centrée : à gauche ("décalé") pointait vers l'équipe A alors
    // qu'elle concerne le match entier.
    Widget? topTime;
    final startsAt = event.startsAt.toDateTime?.toLocal();
    if (startsAt != null) {
      topTime = Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == EventStatusKind.live) ...[const LiveDot(), const SizedBox(width: 4)],
            Text(DateFormat.Hm("fr_FR").format(startsAt), style: textTheme.bodySmall),
            if (!showCountdown) ?_tomorrowCountdown(status, startsAt, textTheme),
          ],
        ),
      );
    }

    // Couronne du vainqueur d'un match terminé (J10) : jamais quand le score est masqué,
    // elle révélerait le résultat (sans spoil, règle 10 de `CLAUDE.md`).
    final showCrown = status == EventStatusKind.finished && !scoresHidden && hasTwoTeams && event.participants.any((p) => p.isWinner == true);
    bool? crownFor(EventParticipantDto p) => showCrown ? p.isWinner == true : null;
    Color? colorFor(EventParticipantDto p) => followedEntityIds.contains(p.entityId) ? AppColors.gold : null;
    final compact = ref.watch(compactEventCardsProvider);

    // Réglages → Affichage : logo, puis son score à côté (pas en dessous),
    // en symétrie avec "VS" au centre — sans les noms.
    Widget? scoreText(num? value) => value == null
        ? null
        : Text("${value.toInt()}", style: AppTextStyles.bodyLargeStrong.copyWith(fontSize: 22, fontWeight: FontWeight.w800));

    final compactRow = compact && hasTwoTeams
        ? Row(
            // Pleine largeur maintenant disponible (cf. plus bas) : mieux vaut
            // répartir logo/score/VS/score/logo dessus que les laisser groupés
            // au centre avec de grandes marges vides de chaque côté.
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TeamBadge(imageUrl: teamA!.imageUrl, diameter: 56, crowned: crownFor(teamA)),
              ?scoreText(score != null ? teamA.score : null),
              centerBadge(20),
              ?scoreText(score != null ? teamB!.score : null),
              TeamBadge(imageUrl: teamB!.imageUrl, diameter: 56, crowned: crownFor(teamB)),
            ],
          )
        : null;

    // Deux moitiés de largeur strictement égale, "VS"/statut posé par-dessus
    // au centre exact (`Stack`) : les deux logos restent parfaitement en
    // miroir quels que soient l'heure ou la longueur des noms.
    final teamsRow = compactRow ??
        (hasTwoTeams
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: _TeamBlock(participant: teamA!, score: score != null ? teamA.score : null, nameColor: colorFor(teamA), crowned: crownFor(teamA)),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _TeamBlock(participant: teamB!, score: score != null ? teamB.score : null, nameColor: colorFor(teamB), crowned: crownFor(teamB)),
                        ),
                      ),
                    ],
                  ),
                  centerBadge(22),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(child: Text(event.name, style: AppTextStyles.bodyLargeStrong, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                ],
              ));

    return Container(
      // Largeur pleine forcée : la ligne compacte (`compactRow`) se dimensionne
      // à son contenu (`MainAxisSize.min`), et le `Column` englobant côté
      // appelant (`_AgendaList`, ...) ne l'étire pas tout seul.
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
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
            child: Stack(
              children: [
                Column(
                  children: [
                    ?topTime,
                    teamsRow,
                    const SizedBox(height: 4),
                    Text(subtitle, style: textTheme.bodySmall),
                  ],
                ),
                // Alerte directement sur la carte (J10), seulement avant le match : en
                // direct ou terminé, "M'alerter au début" n'a plus de sens.
                if (status == EventStatusKind.scheduled)
                  Positioned(top: -AppSpacing.xs, right: -AppSpacing.xs, child: EventAlertBell(eventId: event.id)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo, diminutif et score d'une équipe, centrés — la ligne "–" entre les
/// deux équipes a été retirée : c'est désormais le changement de couleur
/// (`EventCard`) qui sépare visuellement les deux moitiés.
class _TeamBlock extends StatelessWidget {
  const _TeamBlock({required this.participant, required this.score, required this.nameColor, required this.crowned});

  final EventParticipantDto participant;
  final num? score;
  final Color? nameColor;
  final bool? crowned;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            participant.shortName ?? participant.name,
            style: AppTextStyles.bodyLargeStrong.copyWith(fontSize: AppTypography.bodyLarge + 3, color: nameColor),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 4),
        TeamBadge(imageUrl: participant.imageUrl, score: score, diameter: 68, crowned: crowned),
      ],
    );
  }
}

/// Cloche "M'alerter" d'une carte de match (J10) : même abonnement que le bouton
/// "M'alerter au début du match" de l'écran du match (rappel T-15, début, résultat),
/// sans passer par la page du match. Or plein quand l'alerte est active (règle 12).
class EventAlertBell extends ConsumerWidget {
  const EventAlertBell({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = isFollowing(ref.watch(followsProvider).value, FollowTargetType.event, eventId);
    return IconButton(
      tooltip: active ? "Alerte activée" : "M'alerter au début du match",
      visualDensity: VisualDensity.compact,
      icon: Icon(active ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, size: 20),
      color: active ? AppColors.gold : AppColors.textSecondary,
      onPressed: () => toggleEventAlert(context, ref, eventId, active: active),
    );
  }
}

/// Active ou coupe l'alerte d'un match ; le retour optimiste est déjà annulé par
/// `FollowsNotifier` si l'appel échoue, il reste à le dire à l'utilisateur.
Future<void> toggleEventAlert(BuildContext context, WidgetRef ref, String eventId, {required bool active}) async {
  final controller = ref.read(followsControllerProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await (active ? controller.unfollow(FollowTargetType.event, eventId) : controller.follow(FollowTargetType.event, eventId));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text("Impossible de modifier l'alerte.")));
  }
}
