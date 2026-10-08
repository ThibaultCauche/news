import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "package:url_launcher/url_launcher.dart";

import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/competition_follow_button.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../bracket/bracket_provider.dart";
import "../discussion/share_sheet.dart";
import "../next_match/next_match_screen.dart";
import "politics_model.dart";
import "vote_widgets.dart" show SourceNote;

/// Écran 19 (`docs/maquettes/19-suivi-loi.png`) : où en est un texte de loi, étape par étape, façon suivi de colis.
/// Tout vient du dossier législatif officiel ; aucune phrase n'est écrite à la main (règle 9 de CLAUDE.md).
class LawScreen extends ConsumerWidget {
  const LawScreen({super.key, required this.competitionId});

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
          CompetitionFollowButton(competitionId: competitionId, name: detail.value?.name ?? "Texte de loi"),
        ],
      ),
      body: AsyncView(
        value: detail,
        errorMessage: "Impossible de charger ce texte.",
        onRetry: () => ref.invalidate(competitionDetailProvider(competitionId)),
        builder: (competition) {
          final law = competition.law;
          if (law == null) return const Center(child: Text("Ce texte n'a pas de suivi.", style: TextStyle(color: AppColors.textSecondary)));
          return LawBody(law: law);
        },
      ),
    );
  }
}

class LawBody extends StatelessWidget {
  const LawBody({super.key, required this.law});

  final LawDto law;

  String get _statusLine => switch (law.status) {
    LawDtoStatusEnum.promulgated => "Promulguée${law.lawNumber == null ? "" : " · loi n° ${law.lawNumber}"}",
    LawDtoStatusEnum.rejected => "Texte rejeté",
    _ => "En cours d'examen",
  };

  @override
  Widget build(BuildContext context) {
    final author = law.author;
    final votes = [for (final s in law.steps) if (s.vote != null) s];
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        Text(law.lawType, style: const TextStyle(color: AppColors.brass, fontSize: AppTypography.caption, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(law.officialTitle, style: AppTextStyles.cardTitle.copyWith(fontSize: 24, height: 1.25)),
        const SizedBox(height: AppSpacing.sm),
        Text(_statusLine, style: TextStyle(color: law.status == LawDtoStatusEnum.promulgated ? AppColors.win : AppColors.textSecondary, fontSize: AppTypography.bodyLarge)),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel("OÙ EN EST LE TEXTE ?"),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(child: LawTimeline(steps: law.steps.toList())),
        if (author != null) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel("QUI L'A DÉPOSÉ ?"),
          const SizedBox(height: AppSpacing.sm),
          SectionCard(
            child: Row(
              children: [
                const Icon(Icons.account_balance_rounded, color: AppColors.brass),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(authorLabel(author), style: AppTextStyles.bodyLargeStrong),
                      if (cosignersLabel(author.cosigners.toInt()).isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text("et ${cosignersLabel(author.cosigners.toInt())}", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (votes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel("LES VOTES DES DÉPUTÉS"),
          const SizedBox(height: AppSpacing.sm),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (final (i, step) in votes.indexed) ...[
                  if (i > 0) const Divider(height: 1, color: AppColors.surfaceBorder),
                  _VoteRow(step: step),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel("ALLER PLUS LOIN"),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              _Link(icon: Icons.open_in_new_rounded, label: "Dossier complet sur le site de l'Assemblée", url: law.sourceUrl),
              if (law.legifranceUrl != null) ...[
                const Divider(height: 1, color: AppColors.surfaceBorder),
                _Link(icon: Icons.gavel_rounded, label: "Texte publié au Journal officiel (Légifrance)", url: law.legifranceUrl!),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const SourceNote(),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.icon, required this.label, required this.url});

  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
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

/// Un vote du texte : le résultat en une phrase, avec la date de l'étape.
class _VoteRow extends StatelessWidget {
  const _VoteRow({required this.step});

  final LawStepDto step;

  @override
  Widget build(BuildContext context) {
    final vote = step.vote!;
    final eventId = vote.eventId;
    return InkWell(
      onTap: eventId == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: eventId))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md - 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vote.sentence, style: AppTextStyles.bodyStrong),
                  const SizedBox(height: 2),
                  Text(lawDayLabel(step.date), style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                ],
              ),
            ),
            if (eventId != null) const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// La liste d'étapes façon colis : faite (coche), « en ce moment » (rouge, « tu es ici »), à venir (anneau vide),
/// sautée (tiret, un texte rejeté n'a plus de suite).
class LawTimeline extends StatelessWidget {
  const LawTimeline({super.key, required this.steps});

  final List<LawStepDto> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, step) in steps.indexed)
          _StepRow(step: step, isFirst: i == 0, isLast: i == steps.length - 1, previous: i == 0 ? null : steps[i - 1].state),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.isFirst, required this.isLast, required this.previous});

  final LawStepDto step;
  final bool isFirst;
  final bool isLast;
  final LawStepDtoStateEnum? previous;

  @override
  Widget build(BuildContext context) {
    final state = step.state;
    final done = state == LawStepDtoStateEnum.done;
    final current = state == LawStepDtoStateEnum.current;
    final skipped = state == LawStepDtoStateEnum.skipped;
    final labelColor = done || current ? AppColors.textPrimary : AppColors.textSecondary;
    final date = lawDayLabel(step.date);
    final vote = step.vote;
    // Le trait qui descend est plein tant que l'étape est faite : il mène à la suivante.
    final lineBelow = done ? AppColors.textSecondary : AppColors.surfaceBorder;
    final detail = vote?.sentence ?? step.detail;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(width: 2, height: 4, color: isFirst ? Colors.transparent : (previous == LawStepDtoStateEnum.done ? AppColors.textSecondary : AppColors.surfaceBorder)),
                _Dot(state: state),
                Expanded(child: Container(width: 2, color: isLast ? Colors.transparent : lineBelow)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: AppSpacing.md),
              child: Semantics(
                label: "${step.label}. ${switch (state) {
                  LawStepDtoStateEnum.done => "Fait",
                  LawStepDtoStateEnum.current => "En ce moment",
                  LawStepDtoStateEnum.skipped => "Non examiné",
                  _ => "À venir",
                }}. ${date.isEmpty ? "" : date}${detail == null ? "" : ". $detail"}",
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.label,
                        style: AppTextStyles.bodyLargeStrong.copyWith(color: labelColor, decoration: skipped ? TextDecoration.lineThrough : null, decorationColor: AppColors.textTertiary),
                      ),
                      if (current) const Padding(padding: EdgeInsets.only(top: 2), child: Text("En ce moment", style: TextStyle(color: AppColors.live, fontSize: AppTypography.caption, fontWeight: FontWeight.w600))),
                      if (date.isNotEmpty || detail != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            [if (date.isNotEmpty) date, ?detail].join(" · "),
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
                          ),
                        ),
                      if (skipped) const Padding(padding: EdgeInsets.only(top: 2), child: Text("Le texte s'arrête ici", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state});

  final LawStepDtoStateEnum state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case LawStepDtoStateEnum.done:
        return Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 15, color: AppColors.background),
        );
      case LawStepDtoStateEnum.current:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: AppColors.live.withValues(alpha: 0.25), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
        );
      case LawStepDtoStateEnum.skipped:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.textTertiary, width: 1.5)),
          child: const Icon(Icons.remove_rounded, size: 14, color: AppColors.textTertiary),
        );
      default:
        return Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.textTertiary, width: 1.5)));
    }
  }
}
