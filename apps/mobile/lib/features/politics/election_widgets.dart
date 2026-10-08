import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "package:url_launcher/url_launcher.dart";

import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/competition_follow_button.dart";
import "../../widgets/live_badge.dart";
import "../../widgets/ornate_frame.dart";
import "../../widgets/page_title.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../bracket/bracket_provider.dart";
import "../discussion/share_sheet.dart";
import "../next_match/next_match_screen.dart";
import "politics_model.dart";
import "vote_widgets.dart" show SourceNote;

/// Page d'un scrutin (J29c) : sa date, le blocage de 20 h tant qu'il court, puis les territoires suivis avec leur
/// participation et la liste arrivée en tête. Jamais un pronostic : que des résultats officiels, publiés après 20 h.
class ElectionScreen extends ConsumerWidget {
  const ElectionScreen({super.key, required this.competitionId});

  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(competitionDetailProvider(competitionId));
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 56,
        leading: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary)),
        actions: [
          ShareButton(kind: ShareDtoKindEnum.competition, refId: competitionId),
          CompetitionFollowButton(competitionId: competitionId, name: detail.value?.name ?? "Élection"),
        ],
      ),
      body: AsyncView(
        value: detail,
        errorMessage: "Impossible de charger ce scrutin.",
        onRetry: () => ref.invalidate(competitionDetailProvider(competitionId)),
        builder: (competition) {
          final election = competition.election;
          if (election == null) return const Center(child: Text("Ce scrutin n'est pas disponible.", style: TextStyle(color: AppColors.textSecondary)));
          return ElectionOverviewBody(election: election);
        },
      ),
    );
  }
}

class ElectionOverviewBody extends StatelessWidget {
  const ElectionOverviewBody({super.key, required this.election});

  final ElectionOverviewDto election;

  @override
  Widget build(BuildContext context) {
    final territories = election.territories.toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(election.name, style: AppTextStyles.pageTitle, maxLines: 1)),
        const SizedBox(height: 6),
        const BrassRule(),
        const SizedBox(height: AppSpacing.sm),
        Text("${roundLabel(election.round)} · ${electionDateLabel(election.date)}", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.bodyLarge)),
        const SizedBox(height: AppSpacing.lg),
        if (election.embargoed || (territories.isEmpty && !election.hasResults)) _WaitingCard(election: election),
        if (!election.embargoed && election.national != null) ...[
          const SectionLabel("FRANCE ENTIÈRE"),
          const SizedBox(height: AppSpacing.sm),
          NationalCard(result: election.national!),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (!election.embargoed && territories.isNotEmpty) ...[
          SectionLabel(territories.first.level == ElectionTerritoryDtoLevelEnum.department ? "LES DÉPARTEMENTS" : "LES GRANDES VILLES"),
          const SizedBox(height: AppSpacing.sm),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (final (i, t) in territories.indexed) ...[
                  if (i > 0) const Divider(height: 1, color: AppColors.surfaceBorder),
                  _TerritoryRow(territory: t),
                ],
              ],
            ),
          ),
        ],
        if (!election.embargoed && territories.isEmpty && election.hasResults)
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.lg), child: Center(child: Text("Les premiers résultats arrivent après 20 h.", style: TextStyle(color: AppColors.textSecondary)))),
        const SizedBox(height: AppSpacing.lg),
        const _RuleNote(),
        const SizedBox(height: AppSpacing.md),
        const SourceNote(source: "ministère de l'Intérieur (data.gouv.fr)"),
      ],
    );
  }
}

/// La France entière (présidentielle) : participation, saisie des bureaux et les candidats dans l'ordre des voix, tous au même
/// format et dans le même ordre que les résultats d'un territoire.
class NationalCard extends StatelessWidget {
  const NationalCard({super.key, required this.result});

  final ElectionResultDto result;

  @override
  Widget build(BuildContext context) {
    final lists = result.lists.toList();
    final colors = AppColors.series;
    return SectionCard(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.complete) const Stamp("RÉSULTATS COMPLETS", color: AppColors.brass) else const Stamp("DÉPOUILLEMENT EN COURS"),
          const SizedBox(height: AppSpacing.md),
          _MeterRow(label: "Participation", value: result.turnoutPct.toDouble(), caption: "${frInt(result.voters)} votants sur ${frInt(result.registered)} inscrits"),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, l) in lists.indexed) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.surfaceBorder),
            _ListRow(list: l, color: colors[i % colors.length], showSeats: false),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text("${frInt(result.expressed)} suffrages exprimés. Candidats classés par nombre de voix.", style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label)),
        ],
      ),
    );
  }
}

/// Rappel de la règle : pas de résultat avant 20 h, ni estimation, ni pronostic.
class _RuleNote extends StatelessWidget {
  const _RuleNote();

  @override
  Widget build(BuildContext context) => const Text(
    "Le jour du scrutin, aucun résultat n'est publié avant 20 h (article L52-2 du code électoral). L'appli applique ce blocage elle-même, et ne fait ni estimation ni pronostic.",
    textAlign: TextAlign.center,
    style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label),
  );
}

/// Avant les résultats : le cadenas et l'heure de levée du blocage, ou l'attente de la publication officielle.
class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.election});

  final ElectionOverviewDto election;

  @override
  Widget build(BuildContext context) => LockedResultCard(
    embargoed: election.embargoed,
    liftsAt: election.liftsAt,
    waitingText: election.hasResults ? "Les résultats s'afficheront ici dès 20 h." : "Les résultats s'afficheront ici dès leur publication officielle, le soir du scrutin.",
  );
}

class LockedResultCard extends StatelessWidget {
  const LockedResultCard({super.key, required this.embargoed, required this.liftsAt, required this.waitingText});

  final bool embargoed;
  final String liftsAt;
  final String waitingText;

  @override
  Widget build(BuildContext context) {
    final left = liftsInLabel(liftsAt);
    return OrnateFrame(
      strong: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.card), color: AppColors.surface),
        child: Column(
          children: [
            const Icon(Icons.lock_outline_rounded, color: AppColors.brass, size: 32),
            const SizedBox(height: AppSpacing.sm),
            Text(embargoed ? "Résultats à 20 h" : "Résultats le soir du scrutin", style: AppTextStyles.sectionTitle, textAlign: TextAlign.center),
            if (left.isNotEmpty) ...[const SizedBox(height: 4), Text(left, style: const TextStyle(color: AppColors.brass, fontSize: AppTypography.bodyLarge))],
            const SizedBox(height: AppSpacing.sm),
            Text(waitingText, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
          ],
        ),
      ),
    );
  }
}

class _TerritoryRow extends StatelessWidget {
  const _TerritoryRow({required this.territory});

  final ElectionTerritoryDto territory;

  @override
  Widget build(BuildContext context) {
    final leader = territory.leaderLabel;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: territory.eventId))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(territory.name, style: AppTextStyles.bodyLargeStrong),
                  const SizedBox(height: 2),
                  Text(
                    "Participation ${frPercent(territory.turnoutPct)}${leader == null ? "" : " · $leader ${frPercent(territory.leaderPct ?? 0)}"}",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Soirée électorale d'un territoire (écran 25, `docs/maquettes/25-soiree-electorale.png`) : participation, sièges au
/// conseil en hémicycle, voix exprimées par liste.
class ElectionBody extends StatelessWidget {
  const ElectionBody({super.key, required this.election});

  final ElectionDto election;

  @override
  Widget build(BuildContext context) {
    final result = election.result;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        if (result == null) ...[
          Text(election.name, style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSpacing.md),
          LockedResultCard(embargoed: election.embargoed, liftsAt: election.liftsAt, waitingText: "Aucun résultat, estimation ni projection n'est publié avant 20 h le jour du scrutin."),
          const SizedBox(height: AppSpacing.lg),
          const _RuleNote(),
        ] else
          ..._results(result),
        const SizedBox(height: AppSpacing.md),
        const SourceNote(),
      ],
    );
  }

  List<Widget> _results(ElectionResultDto result) {
    final lists = result.lists.toList();
    final colors = AppColors.series;
    final seated = result.totalSeats > 0;
    return [
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(result.territoryName, style: AppTextStyles.pageTitle, maxLines: 1)),
      const SizedBox(height: 6),
      const BrassRule(),
      const SizedBox(height: AppSpacing.sm),
      Text(result.level == ElectionResultDtoLevelEnum.national ? election.name : "${election.name} · ${result.department}", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.bodyLarge)),
      const SizedBox(height: AppSpacing.md),
      SectionCard(
        highlight: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.complete) const Stamp("RÉSULTATS DÉFINITIFS", color: AppColors.brass) else const Stamp("DÉPOUILLEMENT EN COURS"),
            const SizedBox(height: AppSpacing.md),
            _MeterRow(label: "Participation", value: result.turnoutPct.toDouble(), caption: "${frInt(result.voters)} votants sur ${frInt(result.registered)} inscrits"),
            // Seulement pendant le dépouillement : une fois fini, un bureau sans votant (hôpital, prison) ferait croire à un retard
            // (Lyon : 313 bureaux sur 314 dans le fichier définitif).
            if (!result.complete && result.bureaux != null && result.bureaux!.total > 0) ...[
              const SizedBox(height: AppSpacing.md),
              _MeterRow(
                label: "Bureaux dépouillés",
                value: result.bureaux!.counted * 100 / result.bureaux!.total,
                caption: "${result.bureaux!.counted.toInt()} bureaux sur ${result.bureaux!.total.toInt()}",
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text("Blancs : ${frInt(result.blank)} · nuls : ${frInt(result.nulls)}", style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label)),
          ],
        ),
      ),
      if (seated) ...[
        const SizedBox(height: AppSpacing.lg),
        SectionLabel("SIÈGES AU CONSEIL · ${result.totalSeats}"),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: Column(
            children: [
              ColoredHemicycle(seats: [for (final (i, l) in lists.indexed) (count: l.seatsCouncil.toInt(), color: colors[i % colors.length])], label: "Sièges au conseil : ${[for (final l in lists) "${l.label} ${l.seatsCouncil}"].join(", ")}"),
              const SizedBox(height: AppSpacing.sm),
              Text("Majorité : ${result.majoritySeats} sièges (trait pointillé)", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
            ],
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      const SectionLabel("VOIX EXPRIMÉES"),
      const SizedBox(height: AppSpacing.sm),
      SectionCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          children: [
            for (final (i, l) in lists.indexed) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.surfaceBorder),
              _ListRow(list: l, color: colors[i % colors.length], showSeats: seated),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text("${frInt(result.expressed)} suffrages exprimés. ${result.candidates ? "Candidats" : "Listes"} classés par nombre de voix.", style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label)),
      const SizedBox(height: AppSpacing.md),
      TextButton.icon(
        onPressed: () => launchUrl(Uri.parse(result.sourceUrl), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new_rounded, size: 16),
        label: const Text("Fichier officiel du ministère de l'Intérieur"),
      ),
    ];
  }
}

class _MeterRow extends StatelessWidget {
  const _MeterRow({required this.label, required this.value, required this.caption});

  final String label;
  final double value;
  final String caption;

  @override
  Widget build(BuildContext context) => Semantics(
    label: "$label : ${frPercent(value)}. $caption",
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: AppTextStyles.bodyStrong),
              const Spacer(),
              Text(frPercent(value), style: AppTextStyles.bodyLargeStrong),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: AppColors.surfaceBorder)),
                  FractionallySizedBox(widthFactor: (value / 100).clamp(0.0, 1.0), child: const ColoredBox(color: AppColors.textPrimary, child: SizedBox.expand())),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(caption, style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label)),
        ],
      ),
    ),
  );
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.list, required this.color, required this.showSeats});

  final ElectionListDto list;
  final Color color;
  final bool showSeats;

  @override
  Widget build(BuildContext context) {
    final seats = list.seatsCouncil.toInt();
    return Semantics(
      label: "${list.label}${list.head == null ? "" : ", ${list.head}"} : ${frPercent(list.pctExpressed)}, ${frInt(list.votes)} voix${showSeats ? ", $seats sièges" : ""}",
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 5), child: Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle))),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(list.label, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyStrong)),
                  const SizedBox(width: AppSpacing.sm),
                  Text(frPercent(list.pctExpressed), style: AppTextStyles.bodyLargeStrong),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      const Positioned.fill(child: ColoredBox(color: AppColors.surfaceBorder)),
                      FractionallySizedBox(widthFactor: (list.pctExpressed / 100).clamp(0.0, 1.0).toDouble(), child: ColoredBox(color: color, child: const SizedBox.expand())),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [if (list.head != null) "Tête de liste : ${list.head}", "${frInt(list.votes)} voix", if (showSeats) "$seats siège${seats > 1 ? "s" : ""}"].join(" · "),
                style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hémicycle dont chaque part est une couleur : les sièges sont rangés liste après liste, du plus de voix au moins.
/// Le trait pointillé du centre marque la moitié des sièges (majorité absolue au-delà).
class ColoredHemicycle extends StatelessWidget {
  const ColoredHemicycle({super.key, required this.seats, required this.label});

  final List<({int count, Color color})> seats;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = [for (final s in seats) ...List.filled(s.count, s.color)];
    final positions = hemicycleSeats(colors.length);
    return Semantics(
      label: label,
      image: true,
      child: ExcludeSemantics(
        child: AspectRatio(aspectRatio: 2 / 1.08, child: CustomPaint(painter: _ColoredHemicyclePainter(positions: positions, colors: colors, dotFraction: hemicycleDotFraction(colors.length)))),
      ),
    );
  }
}

class _ColoredHemicyclePainter extends CustomPainter {
  _ColoredHemicyclePainter({required this.positions, required this.colors, required this.dotFraction});

  final List<Offset> positions;
  final List<Color> colors;
  final double dotFraction;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    final radius = (size.width / 2 - pad).clamp(0.0, size.height - pad);
    final center = Offset(size.width / 2, size.height - pad);
    final dot = radius * dotFraction;
    for (var i = 0; i < positions.length && i < colors.length; i++) {
      canvas.drawCircle(center + Offset(positions[i].dx * radius, -positions[i].dy * radius), dot, Paint()..color = colors[i]);
    }
    // Trait pointillé du centre : la moitié des sièges.
    final line = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 1.2;
    for (var y = center.dy; y > center.dy - radius - 6; y -= 8) {
      canvas.drawLine(Offset(center.dx, y), Offset(center.dx, y - 4), line);
    }
  }

  @override
  bool shouldRepaint(_ColoredHemicyclePainter old) => old.colors != colors || old.dotFraction != dotFraction;
}
