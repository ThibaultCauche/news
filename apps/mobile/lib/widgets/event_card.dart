import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "package:palette_generator/palette_generator.dart";
import "../core/date_x.dart";
import "../core/settings_provider.dart";
import "../domain/event_status.dart";
import "../theme/app_theme.dart";
import "ornate_frame.dart";
import "../features/follows/follows_provider.dart";
import "../theme/tokens.dart";
import "live_dot.dart";
import "match_countdown.dart";
import "match_visuals.dart";
import "spoiler_hold.dart";

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
    this.banner = false,
    this.footer,
    this.framed = true,
  });

  /// Cadre fin à pointes ; désactivé quand la carte est déjà dans une carte cadrée (« Tes suivis »).
  final bool framed;

  /// Bandeau « en direct » de l'Accueil (J10) : même carte que partout, teintée en rouge
  /// (couleur du direct, règle 12 de `CLAUDE.md`) et libellée « EN DIRECT » à la place de l'heure.
  final bool banner;

  /// Ligne sous la carte, dans son cadre (ex. « Ensuite : … » du bandeau en direct).
  final Widget? footer;

  /// Score d'un match terminé masqué (réglage sans spoil du compte).
  final bool scoresHidden;

  final EventSummaryDto event;
  final VoidCallback? onTap;

  /// `entityId` des équipes/joueurs suivis : affichés en or
  /// (`docs/maquettes/specs/01-valorant-saison.md`, `06-groupes.md`), comme
  /// `highlightedEventIds` dans `bracket_screen.dart`.
  final Set<String> followedEntityIds;

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
    // Sans spoil : le score d'un match terminé reste sur la carte, flouté ; un appui long le
    // dissipe petit à petit (J11) et le révèle pour la session, carte et écran du match ensemble.
    final hidden = scoresHidden && !ref.watch(revealedEventsProvider).contains(event.id);
    // Un match à venir n'a pas de score : l'API renvoie 0-0, à ne pas afficher.
    final score = status == EventStatusKind.scheduled ? null : _scoreLine;
    final blurScores = status == EventStatusKind.finished && hidden && score != null;
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
    // Compte à rebours à la place du "VS" pour un match à venir dans les 24 h (J10) ; plus loin,
    // le "VS" habituel : l'heure suffit, un décompte de plusieurs jours n'apprend rien.
    final start = event.startsAt.toDateTime;
    final untilStart = start?.difference(DateTime.now());
    final countdownTarget = status == EventStatusKind.scheduled && untilStart != null && untilStart > Duration.zero && untilStart <= const Duration(hours: 24)
        ? start
        : null;
    Widget centerBadge(double fontSize) => status == EventStatusKind.postponed
        ? Text(status.label, style: textTheme.bodySmall?.copyWith(color: status.color))
        : countdownTarget != null
        // 72 % du "VS" : HH:MM:SS doit tenir entre les deux logos (≈ 88 px sur un écran de 360 dp).
        ? MatchCountdown(startsAt: countdownTarget, fontSize: fontSize * 0.72)
        : Text(
            "VS",
            style: AppTextStyles.versus(fontSize),
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
            if (banner && status == EventStatusKind.live)
              Text("EN DIRECT", style: textTheme.labelSmall?.copyWith(color: AppColors.live))
            else
              Text(DateFormat.Hm("fr_FR").format(startsAt), style: textTheme.bodySmall),
          ],
        ),
      );
    }

    // Couronne du vainqueur d'un match terminé (J10) : jamais quand le score est masqué,
    // elle révélerait le résultat (sans spoil, règle 10 de `CLAUDE.md`).
    final showCrown = status == EventStatusKind.finished && !hidden && hasTwoTeams && event.participants.any((p) => p.isWinner == true);
    bool? crownFor(EventParticipantDto p) => showCrown ? p.isWinner == true : null;
    Color? colorFor(EventParticipantDto p) => followedEntityIds.contains(p.entityId) ? AppColors.gold : null;
    final compact = ref.watch(compactEventCardsProvider);

    // Réglages → Affichage : logo, puis son score à côté (pas en dessous),
    // en symétrie avec "VS" au centre — sans les noms.
    // `sigma` : flou courant du score (0 = net), piloté par l'appui long (`SpoilerHold`).
    Widget buildTeams(double sigma) {
    Widget? scoreText(num? value) => value == null
        ? null
        : SpoilerBlur(
            sigma: sigma,
            child: Text("${value.toInt()}", style: AppTextStyles.bodyLargeStrong.copyWith(fontSize: 22, fontWeight: FontWeight.w800)),
          );

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
    return compactRow ??
        (hasTwoTeams
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: _TeamBlock(participant: teamA!, score: score != null ? teamA.score : null, scoreSigma: sigma, nameColor: colorFor(teamA), crowned: crownFor(teamA)),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _TeamBlock(participant: teamB!, score: score != null ? teamB.score : null, scoreSigma: sigma, nameColor: colorFor(teamB), crowned: crownFor(teamB)),
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
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(event.name, style: AppTextStyles.bodyLargeStrong, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                        // Équipes pas encore connues : le compte à rebours reste utile.
                        if (countdownTarget != null) ...[const SizedBox(height: 4), MatchCountdown(startsAt: countdownTarget, fontSize: 20)],
                      ],
                    ),
                  ),
                ],
              ));
    }

    final teamsRow = blurScores
        ? SpoilerHold(builder: (context, sigma) => buildTeams(sigma), onReveal: () => ref.read(revealedEventsProvider.notifier).reveal(event.id))
        : buildTeams(0);

    final strong = isHighStakes(event.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: OrnateFrame(
      enabled: framed,
      radius: AppRadii.card,
      strong: strong,
      color: banner ? AppColors.live : AppColors.brass,
      child: Container(
      // Largeur pleine forcée : la ligne compacte (`compactRow`) se dimensionne
      // à son contenu (`MainAxisSize.min`), et le `Column` englobant côté
      // appelant (`_AgendaList`, ...) ne l'étire pas tout seul.
      width: double.infinity,
      decoration: BoxDecoration(
        color: banner ? AppColors.live.withValues(alpha: 0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        gradient: banner ? null : teamsGradient(colorA, colorB),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // Réclame l'appui long : sans lui, relâcher après avoir maintenu pour révéler le score
          // ouvrirait quand même le match.
          onLongPress: blurScores ? () {} : null,
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
                    if (footer != null) ...[
                      const Divider(height: AppSpacing.lg),
                      footer!,
                    ],
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
    ),
    ),
    );
  }
}

/// Logo, diminutif et score d'une équipe, centrés — la ligne "–" entre les
/// deux équipes a été retirée : c'est désormais le changement de couleur
/// (`EventCard`) qui sépare visuellement les deux moitiés.
class _TeamBlock extends StatelessWidget {
  const _TeamBlock({required this.participant, required this.score, this.scoreSigma = 0, required this.nameColor, required this.crowned});

  final EventParticipantDto participant;
  final num? score;
  final double scoreSigma;
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
        TeamBadge(imageUrl: participant.imageUrl, score: score, scoreSigma: scoreSigma, diameter: 68, crowned: crowned),
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
      // Cible réduite (36×32) : la cloche reste dans la ligne de l'heure et ne touche pas
      // le nom de l'équipe de droite, juste en dessous.
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 32),
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
