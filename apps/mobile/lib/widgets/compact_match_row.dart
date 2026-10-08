import "dart:math" as math;
import "dart:ui" as ui;
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../core/date_x.dart";
import "../domain/event_status.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";
import "event_card.dart";
import "live_badge.dart";
import "match_visuals.dart";
import "ornate_frame.dart";
import "spoiler_hold.dart";
import "../features/formula1/f1_widgets.dart" show SessionPodium;

/// Ligne de match compacte des listes (J22, #A2) : heure ou statut à gauche, les deux équipes
/// l'une sous l'autre avec leur logo et leur score, cloche à droite avant le match. 56 px de haut :
/// 8 à 10 matchs par écran. La grande `EventCard` reste pour l'écran du match et « Maintenant pour toi ».
/// Même identité que la grande carte : fond teinté des couleurs des deux équipes (rouge en direct),
/// cadre fin à pointes en laiton (rouge en direct, renforcé pour une finale ou une élimination),
/// heure et scores en Cinzel. Sans spoil : le score d'un match terminé est flouté et se révèle par
/// appui long, comme sur la grande carte.
class CompactMatchRow extends ConsumerWidget {
  const CompactMatchRow({super.key, required this.event, required this.scoresHidden, this.onTap, this.followedEntityIds = const {}});

  static const height = 56.0;

  /// Marge égale à gauche et à droite : la place de l'heure et de la cloche, pour centrer le VS sur la carte.
  static const _reserved = 54.0;

  final EventSummaryDto event;
  final bool scoresHidden;
  final VoidCallback? onTap;
  final Set<String> followedEntityIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = event.status.statusKind;
    final hidden = scoresHidden && !ref.watch(revealedEventsProvider).contains(event.id);
    final finished = status == EventStatusKind.finished;
    final live = status == EventStatusKind.live;
    final showScores = live || finished;
    final blur = finished && hidden;
    final teams = event.participants;

    Color? accentOf(EventParticipantDto? p) {
      final url = p?.imageUrl;
      return url == null ? null : ref.watch(entityAccentColorProvider(url)).value;
    }

    // Même composition que la grande carte, sur une ligne : logo + nom, score VS score, nom + logo.
    // Le VS est au centre exact de la carte : l'heure (à gauche) et la cloche (à droite) flottent
    // dessus, et des marges égales de chaque côté les réservent. Les scores ont une largeur fixe
    // pour que les espacements ne bougent pas avec les chiffres.
    Widget rows(double sigma) {
      final a = teams[0], b = teams[1];
      // Les deux blocs ont la largeur du plus long des deux noms : le logo du nom court s'écarte du centre
      // pour garder la symétrie (« PR » face à « LOUD »).
      final nameWidth = math.max(_Side.measure(context, a), _Side.measure(context, b));
      bool bold(EventParticipantDto p) => finished && !hidden && p.isWinner == true;
      Widget score(EventParticipantDto p) => SizedBox(
        width: 16,
        child: Center(
          child: showScores && p.score != null ? SpoilerBlur(sigma: sigma, child: Text("${p.score!.toInt()}", style: AppTextStyles.score(19))) : null,
        ),
      );
      return Row(
        children: [
          Expanded(child: _Side(participant: a, nameWidth: nameWidth, mirrored: false, highlight: followedEntityIds.contains(a.entityId), bold: bold(a))),
          const SizedBox(width: 4),
          if (showScores) score(a),
          Text("VS", style: AppTextStyles.versus(13).copyWith(color: AppColors.brass)),
          if (showScores) score(b),
          const SizedBox(width: 4),
          Expanded(child: _Side(participant: b, nameWidth: nameWidth, mirrored: true, highlight: followedEntityIds.contains(b.entityId), bold: bold(b))),
        ],
      );
    }

    // Une session de F1 (J28) : son nom, et le podium une fois terminée (flouté en sans spoil, comme un score).
    final body = event.kind == "session"
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(event.name, style: AppTextStyles.bodyLargeStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (finished && teams.isNotEmpty) SessionPodium(event: event, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption, fontWeight: FontWeight.w600)),
            ],
          )
        : teams.length != 2
        ? Text(event.name, style: AppTextStyles.bodyLargeStrong, overflow: TextOverflow.ellipsis)
        : (blur ? SpoilerHold(builder: (context, sigma) => rows(sigma), onReveal: () => ref.read(revealedEventsProvider.notifier).reveal(event.id)) : rows(0));

    final decoration = BoxDecoration(
      color: live ? AppColors.live.withValues(alpha: 0.12) : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.card),
      gradient: live || teams.length != 2 ? null : teamsGradient(accentOf(teams[0]), accentOf(teams[1])),
    );
    return SizedBox(
      height: height,
      child: OrnateFrame(
        radius: AppRadii.card,
        strong: isHighStakes(event.name),
        color: live ? AppColors.live : AppColors.brass,
        child: DecoratedBox(
          decoration: decoration,
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(AppRadii.card),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              // Réclame l'appui long : sans lui, relâcher après avoir maintenu pour révéler ouvrirait le match.
              onLongPress: blur ? () {} : null,
              child: Stack(
                children: [
                  Positioned.fill(child: Padding(padding: const EdgeInsets.symmetric(horizontal: _reserved, vertical: 6), child: Align(child: body))),
                  Positioned(left: AppSpacing.sm + 2, top: 0, bottom: 0, width: _reserved - AppSpacing.sm, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _StatusColumn(event: event, status: status))),
                  if (status == EventStatusKind.scheduled) Positioned(right: 0, top: 0, bottom: 0, child: Center(child: EventAlertBell(eventId: event.id))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusColumn extends StatelessWidget {
  const _StatusColumn({required this.event, required this.status});

  final EventSummaryDto event;
  final EventStatusKind status;

  @override
  Widget build(BuildContext context) {
    final start = event.startsAt.toDateTime?.toLocal();
    final time = start == null ? "" : DateFormat.Hm("fr_FR").format(start);
    final small = Theme.of(context).textTheme.labelSmall;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: switch (status) {
        EventStatusKind.live => [const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Stamp("DIRECT", fontSize: 9))],
        EventStatusKind.finished => [
          Text(time, style: AppTextStyles.versus(14)),
          const SizedBox(height: 2),
          Text("TERMINÉ", style: small?.copyWith(color: AppColors.textTertiary, fontSize: 9, letterSpacing: 0.8)),
        ],
        EventStatusKind.postponed || EventStatusKind.cancelled => [Text(status.label, style: small?.copyWith(color: status.color))],
        _ => [Text(time, style: AppTextStyles.versus(16))],
      },
    );
  }
}

/// Un côté de la ligne : bloc logo + nom collé au centre (logo puis nom à gauche, nom puis logo à droite).
class _Side extends StatelessWidget {
  const _Side({required this.participant, required this.nameWidth, required this.mirrored, required this.highlight, required this.bold});

  final EventParticipantDto participant;

  /// Largeur réservée au nom : celle du plus long des deux noms du match.
  final double nameWidth;
  final bool mirrored;
  final bool highlight;
  final bool bold;

  static const _logo = 24.0;
  static const _wantedGap = 6.0;

  static String _label(EventParticipantDto p) => p.shortName ?? p.name;

  static TextStyle _style({bool bold = false, bool highlight = false}) =>
      TextStyle(fontSize: AppTypography.bodyLarge, fontWeight: bold || highlight ? FontWeight.w700 : FontWeight.w500, color: highlight ? AppColors.gold : AppColors.textPrimary);

  /// Largeur du nom à sa taille normale (en gras, la plus large des graisses utilisées).
  static double measure(BuildContext context, EventParticipantDto p) {
    final painter = TextPainter(text: TextSpan(text: _label(p), style: _style(bold: true)), maxLines: 1, textDirection: ui.TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context))..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final logo = participant.imageUrl;
    final badge = SizedBox(width: _logo, height: _logo, child: logo == null ? null : TeamLogo(imageUrl: logo, size: _logo));
    return LayoutBuilder(
      builder: (context, constraints) {
        // Un peu d'air entre le logo et le nom, seulement s'il reste de la place pour le nom en entier ;
        // sinon pas d'espace et le nom rétrécit pour tenir.
        final fits = constraints.maxWidth - _logo - _wantedGap >= nameWidth;
        final gap = SizedBox(width: fits ? _wantedGap : 0);
        final width = math.min(nameWidth, math.max(0.0, constraints.maxWidth - _logo - (fits ? _wantedGap : 0)));
        // Le nom court est centré dans la largeur du plus long : autant d'air entre son logo et le VS.
        final name = SizedBox(
          width: width,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(_label(participant), maxLines: 1, style: _style(bold: bold, highlight: highlight)),
          ),
        );
        return Row(
          mainAxisAlignment: mirrored ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: mirrored ? [name, gap, badge] : [badge, gap, name],
        );
      },
    );
  }
}
