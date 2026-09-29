import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "package:palette_generator/palette_generator.dart";
import "../core/date_x.dart";
import "../core/settings_provider.dart";
import "../domain/event_status.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";
import "live_dot.dart";

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
  });

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
    final score = status == EventStatusKind.finished && scoresHidden ? null : _scoreLine;
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
    Widget centerBadge(double fontSize) => status == EventStatusKind.postponed
        ? Text(status.label, style: textTheme.bodySmall?.copyWith(color: status.color))
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
            ?_tomorrowCountdown(status, startsAt, textTheme),
          ],
        ),
      );
    }

    Color? colorFor(EventParticipantDto p) => followedEntityIds.contains(p.entityId) ? AppColors.gold : null;
    final compact = ref.watch(compactEventCardsProvider);

    // Réglages → Affichage : logo, puis son score à côté (pas en dessous),
    // en symétrie avec "VS" au centre — sans les noms.
    Widget? scoreText(num? value) => value == null
        ? null
        : Text("${value.toInt()}", style: AppTextStyles.bodyLargeStrong.copyWith(fontSize: 20, fontWeight: FontWeight.w800));

    final compactRow = compact && hasTwoTeams
        ? Row(
            // Pleine largeur maintenant disponible (cf. plus bas) : mieux vaut
            // répartir logo/score/VS/score/logo dessus que les laisser groupés
            // au centre avec de grandes marges vides de chaque côté.
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _TeamBadge(imageUrl: teamA!.imageUrl, diameter: 32),
              ?scoreText(score != null ? teamA.score : null),
              centerBadge(16),
              ?scoreText(score != null ? teamB!.score : null),
              _TeamBadge(imageUrl: teamB!.imageUrl, diameter: 32),
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
                          child: _TeamBlock(participant: teamA!, score: score != null ? teamA.score : null, nameColor: colorFor(teamA)),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _TeamBlock(participant: teamB!, score: score != null ? teamB.score : null, nameColor: colorFor(teamB)),
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
        gradient: (colorA == null && colorB == null)
            ? null
            : LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  (colorA ?? AppColors.surface).withValues(alpha: colorA != null ? 0.26 : 0),
                  AppColors.surface,
                  (colorB ?? AppColors.surface).withValues(alpha: colorB != null ? 0.26 : 0),
                ],
              ),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
            child: Column(
              children: [
                ?topTime,
                teamsRow,
                const SizedBox(height: 4),
                Text(subtitle, style: textTheme.bodySmall),
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
  const _TeamBlock({required this.participant, required this.score, required this.nameColor});

  final EventParticipantDto participant;
  final num? score;
  final Color? nameColor;

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
        _TeamBadge(imageUrl: participant.imageUrl, score: score),
      ],
    );
  }
}

class _TeamBadge extends StatelessWidget {
  const _TeamBadge({required this.imageUrl, this.score, this.diameter = 44});

  final String? imageUrl;
  final num? score;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Coin arrondi plutôt que cercle : certains logos (bannières larges
        // type "LOBA SPORT", blasons non circulaires) ne remplissaient pas
        // un cercle proprement et semblaient déborder dessus. `BoxFit.contain`
        // reste nécessaire, tous les logos ne sont pas carrés.
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.chip * diameter / 44),
          child: Container(
            width: diameter,
            height: diameter,
            color: AppColors.surfaceBorder,
            child: imageUrl != null ? Image.network(imageUrl!, fit: BoxFit.contain) : null,
          ),
        ),
        if (score != null) ...[
          const SizedBox(height: 2),
          Text(
            "${score!.toInt()}",
            // Taille de score proportionnelle au logo (44 → 26, la tuile
            // réduite a un logo plus petit donc un score plus petit aussi).
            style: AppTextStyles.bodyLargeStrong.copyWith(fontSize: AppTypography.heroScore * diameter / 44, fontWeight: FontWeight.w800),
          ),
        ],
      ],
    );
  }
}
