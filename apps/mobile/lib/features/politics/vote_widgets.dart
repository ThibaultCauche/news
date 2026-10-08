import "dart:math" as math;

import "package:flutter/material.dart";
import "package:news_api_client/news_api_client.dart";
import "package:url_launcher/url_launcher.dart";

import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/ornate_frame.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "law_screen.dart";
import "politics_model.dart";

/// Point d'un siège : plein blanc (pour), plein laiton (contre), anneau (abstention), petit point pâle (absent).
/// Quatre formes distinctes, jamais la couleur seule (règle 12).
void paintSeat(Canvas canvas, Offset at, double radius, SeatKind kind) {
  switch (kind) {
    case SeatKind.pour:
      canvas.drawCircle(at, radius, Paint()..color = AppColors.textPrimary);
    case SeatKind.contre:
      canvas.drawCircle(at, radius, Paint()..color = AppColors.brass);
    case SeatKind.abstention:
      canvas.drawCircle(
        at,
        radius * 0.8,
        Paint()
          ..color = AppColors.textPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, radius * 0.4),
      );
    case SeatKind.absent:
      canvas.drawCircle(at, radius * 0.45, Paint()..color = AppColors.textTertiary);
  }
}

/// L'hémicycle d'un vote : un point par député, rangé groupe après groupe, du plus à gauche de l'écran au plus à droite
/// dans l'ordre alphabétique des noms officiels (aucun ordre politique).
class Hemicycle extends StatelessWidget {
  const Hemicycle({super.key, required this.groups, required this.summary});

  final List<VoteGroupDto> groups;

  /// Phrase pour les lecteurs d'écran : « 312 pour, 198 contre… ».
  final String summary;

  @override
  Widget build(BuildContext context) {
    final kinds = seatKinds(groups);
    final seats = hemicycleSeats(kinds.length);
    return Semantics(
      label: "Hémicycle : $summary",
      image: true,
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: 2 / 1.08,
          child: CustomPaint(painter: _HemiclyclePainter(seats: seats, kinds: kinds, dotFraction: hemicycleDotFraction(kinds.length))),
        ),
      ),
    );
  }
}

class _HemiclyclePainter extends CustomPainter {
  _HemiclyclePainter({required this.seats, required this.kinds, required this.dotFraction});

  final List<Offset> seats;
  final List<SeatKind> kinds;
  final double dotFraction;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    final radius = (size.width / 2 - pad).clamp(0.0, size.height - pad);
    final center = Offset(size.width / 2, size.height - pad);
    final dot = radius * dotFraction;
    for (var i = 0; i < seats.length && i < kinds.length; i++) {
      paintSeat(canvas, center + Offset(seats[i].dx * radius, -seats[i].dy * radius), dot, kinds[i]);
    }
  }

  @override
  bool shouldRepaint(_HemiclyclePainter old) => old.kinds != kinds || old.dotFraction != dotFraction;
}

/// Pastille de légende : la forme d'un siège dessinée à petite échelle.
class SeatGlyph extends StatelessWidget {
  const SeatGlyph(this.kind, {super.key, this.size = 12});

  final SeatKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _GlyphPainter(kind));
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind);

  final SeatKind kind;

  @override
  void paint(Canvas canvas, Size size) => paintSeat(canvas, size.center(Offset.zero), size.width / 2.2, kind);

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind;
}

class VoteLegend extends StatelessWidget {
  const VoteLegend({super.key, required this.pour, required this.contre, required this.abst, required this.absent});

  final int pour;
  final int contre;
  final int abst;
  final int absent;

  @override
  Widget build(BuildContext context) {
    Widget item(SeatKind kind, String label, int count) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SeatGlyph(kind),
        const SizedBox(width: 6),
        Text("$label ", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
        Text("$count", style: AppTextStyles.captionStrong),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [item(SeatKind.pour, "Pour", pour), item(SeatKind.contre, "Contre", contre), item(SeatKind.abstention, "Abstention", abst), item(SeatKind.absent, "Absents", absent)],
    );
  }
}

/// Écran d'un vote de l'Assemblée (J29) : le résultat en une phrase, l'hémicycle, puis chaque groupe avec sa position.
class ScrutinBody extends StatelessWidget {
  const ScrutinBody({super.key, required this.vote});

  final ScrutinDto vote;

  @override
  Widget build(BuildContext context) {
    final groups = vote.groups.toList();
    // Un député qui n'a pas voté n'est pas toujours déclaré « non-votant » : les absents sont tous les sièges sans voix.
    final seatTotal = groups.fold<int>(0, (sum, g) => sum + math.max(g.members.toInt(), g.pour.toInt() + g.contre.toInt() + g.abst.toInt() + g.nonVotants.toInt()));
    final absent = math.max(0, seatTotal - vote.pour.toInt() - vote.contre.toInt() - vote.abst.toInt());
    final summary = "${vote.pour} pour, ${vote.contre} contre, ${vote.abst} abstentions, $absent absents";
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        OrnateFrame(
          strong: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.card), color: AppColors.surface),
            child: Column(
              children: [
                SectionLabel("VOTE À L'ASSEMBLÉE · ${lawDayLabel(vote.date).toUpperCase()}"),
                const SizedBox(height: AppSpacing.sm),
                Text(vote.lawName ?? "Vote sur l'ensemble du texte", textAlign: TextAlign.center, style: AppTextStyles.cardTitle),
                const SizedBox(height: AppSpacing.md),
                Text(vote.sentence, textAlign: TextAlign.center, style: AppTextStyles.sectionTitle),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "${vote.voteType == null ? "Scrutin public" : _capitalize(vote.voteType!)} · majorité requise : ${vote.majority} voix",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel("L'HÉMICYCLE"),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: Column(
            children: [
              Hemicycle(groups: groups, summary: summary),
              const SizedBox(height: AppSpacing.sm),
              VoteLegend(pour: vote.pour.toInt(), contre: vote.contre.toInt(), abst: vote.abst.toInt(), absent: absent),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                "Un point par député, rangés groupe après groupe dans l'ordre alphabétique de leur nom officiel.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel("VOTE PAR GROUPE"),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (final (i, group) in groups.indexed) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.surfaceBorder),
                GroupVoteRow(group: group),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          "La position d'un groupe est celle de la majorité de ses voix exprimées, calculée à partir des décomptes officiels.",
          style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel("ALLER PLUS LOIN"),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              if (vote.lawId != null)
                _LinkRow(
                  icon: Icons.route_rounded,
                  label: "Où en est ce texte ?",
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LawScreen(competitionId: vote.lawId!))),
                ),
              if (vote.lawId != null) const Divider(height: 1, color: AppColors.surfaceBorder),
              _LinkRow(icon: Icons.open_in_new_rounded, label: "Scrutin n° ${vote.numero} sur le site de l'Assemblée", onTap: () => launchUrl(Uri.parse(vote.sourceUrl), mode: LaunchMode.externalApplication)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const SourceNote(),
      ],
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Mention de la source et de la licence, au pied de chaque écran de politique (règle 8 de CLAUDE.md).
class SourceNote extends StatelessWidget {
  const SourceNote({super.key, this.source = "Assemblée nationale"});

  final String source;

  @override
  Widget build(BuildContext context) => Text(
    "Source : $source, données publiques sous Licence ouverte 2.0. Aucun commentaire sur le fond : seulement les faits officiels.",
    textAlign: TextAlign.center,
    style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label),
  );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md - 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.brass),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(child: Text(label, style: AppTextStyles.body)),
          const Icon(Icons.chevron_right, color: AppColors.textTertiary),
        ],
      ),
    ),
  );
}

/// Un groupe dans un vote : son nom officiel, sa position, et une barre dont chaque part est une forme de siège.
class GroupVoteRow extends StatelessWidget {
  const GroupVoteRow({super.key, required this.group});

  final VoteGroupDto group;

  @override
  Widget build(BuildContext context) {
    final pour = group.pour.toInt(), contre = group.contre.toInt(), abst = group.abst.toInt();
    // Les membres du groupe qui n'ont pas voté (absents ou non-votants déclarés).
    final absent = math.max(group.members.toInt() - pour - contre - abst, group.nonVotants.toInt());
    final total = pour + contre + abst + absent;
    final position = group.position.name;
    final label = positionLabel(position);
    return Semantics(
      label: "${group.name} : $label. $pour pour, $contre contre, $abst abstentions.",
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(group.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyStrong)),
                  const SizedBox(width: AppSpacing.sm),
                  Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      if (pour > 0) Expanded(flex: pour, child: const ColoredBox(color: AppColors.textPrimary, child: SizedBox.expand())),
                      if (contre > 0) Expanded(flex: contre, child: const ColoredBox(color: AppColors.brass, child: SizedBox.expand())),
                      if (abst > 0) Expanded(flex: abst, child: const ColoredBox(color: AppColors.textSecondary, child: SizedBox.expand())),
                      if (absent > 0) Expanded(flex: absent, child: const ColoredBox(color: AppColors.surfaceBorder, child: SizedBox.expand())),
                      if (total == 0) const Expanded(child: ColoredBox(color: AppColors.surfaceBorder, child: SizedBox.expand())),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "$pour pour · $contre contre · $abst abst. · $absent ${absent > 1 ? "absents" : "absent"}",
                style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
