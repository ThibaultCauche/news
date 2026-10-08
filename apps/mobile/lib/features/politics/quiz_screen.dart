import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "package:url_launcher/url_launcher.dart";

import "../../core/api_providers.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/ornate_frame.dart";
import "../../widgets/page_title.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../next_match/next_match_screen.dart";
import "politics_model.dart";
import "politics_screen.dart" show OutcomeBar;
import "vote_widgets.dart";

final quizProvider = FutureProvider.autoDispose<QuizDto>((ref) async {
  final response = await ref.watch(apiClientProvider).getPoliticsApi().politicsControllerGetQuiz();
  return response.data!;
});

/// Envoie une réponse et rend la correction du serveur ; un provider pour que les tests puissent le remplacer.
final quizAnswerProvider = Provider<Future<QuizAnswerResultDto> Function(QuizQuestionDto question, String choice)>((ref) {
  return (question, choice) async {
    final response = await ref.read(apiClientProvider).getPoliticsApi().politicsControllerAnswer(
      quizAnswerBodyDto: QuizAnswerBodyDto((b) => b
        ..questionId = question.id
        ..choice = QuizAnswerBodyDtoChoiceEnum.valueOf(choice)),
    );
    return response.data!;
  };
});

const _choices = [("pour", "Pour", SeatKind.pour), ("contre", "Contre", SeatKind.contre), ("abstention", "Abstention", SeatKind.abstention)];

/// « Qui a voté ? » (J29b, `docs/maquettes/16-jeu-du-jour.png`) : cinq questions par jour, « comment ce groupe a-t-il voté
/// sur ce texte ? ». Les mêmes pour tout le monde, les groupes interrogés à tour de rôle, la source officielle avec chaque
/// réponse, aucun commentaire sur le fond. Aucun point : seulement une série de jours (`docs/07`).
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  /// Corrections reçues pendant cette séance, par question : sans compte, c'est la seule mémoire du jeu.
  final Map<String, QuizAnswerResultDto> _results = {};
  bool _busy = false;
  // Question dont on lit la correction : on reste dessus jusqu'à « Question suivante ».
  String? _shownId;

  Future<void> _answer(QuizQuestionDto question, String choice) async {
    if (_busy) return;
    setState(() => _busy = true);
    await runOrShowError(context, () async {
      final result = await ref.read(quizAnswerProvider)(question, choice);
      // La correction reste affichée jusqu'à « Question suivante ».
      if (mounted) {
        setState(() {
          _results[question.id] = result;
          _shownId = question.id;
        });
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final quiz = ref.watch(quizProvider);
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 56,
        leading: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary)),
      ),
      body: AsyncView(
        value: quiz,
        errorMessage: "Impossible de charger le quiz.",
        onRetry: () => ref.invalidate(quizProvider),
        builder: (data) => _body(data),
      ),
    );
  }

  bool _isDone(QuizDto quiz, QuizQuestionDto q) => q.myChoice != null || _results.containsKey(q.id);

  Widget _body(QuizDto quiz) {
    final questions = quiz.questions.toList();
    if (questions.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Text("Pas encore de question aujourd'hui : reviens bientôt.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary))));
    }
    // Reste sur la question qu'on vient de répondre ; sinon la première sans réponse ; sinon le bilan.
    final shown = questions.where((q) => q.id == _shownId).firstOrNull;
    final next = questions.where((q) => !_isDone(quiz, q)).firstOrNull;
    final current = shown != null && _results.containsKey(shown.id) ? shown : next;
    final header = _Header(quiz: quiz, current: current == null ? questions.length + 1 : questions.indexOf(current) + 1, total: questions.length);
    if (current == null) return _Summary(quiz: quiz, questions: questions, results: _results, header: header);
    final result = _results[current.id];
    final last = questions.where((q) => !_isDone(quiz, q)).isEmpty;
    // Le bouton « Question suivante » est ancré en bas, toujours au même endroit (règle 15) : vérifié sur un téléphone,
    // posé dans la liste il restait sous le pli une fois la correction affichée.
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            children: [
              header,
              const SizedBox(height: AppSpacing.md),
              _QuestionCard(question: current),
              const SizedBox(height: AppSpacing.md),
              if (result == null)
                for (final (value, label, kind) in _choices) ...[_ChoiceButton(label: label, kind: kind, enabled: !_busy, onTap: () => _answer(current, value)), const SizedBox(height: AppSpacing.sm)]
              else
                _ResultCard(result: result),
              const SizedBox(height: AppSpacing.lg),
              const _Neutrality(),
            ],
          ),
        ),
        if (result != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => setState(() {
                    _shownId = null;
                    // Dernière question : le bilan se recharge pour recompter la série.
                    if (last) ref.invalidate(quizProvider);
                  }),
                  child: Text(last ? "Voir mon score" : "Question suivante"),
                ),
              ),
            ),
          ),
      ],
    );
  }

}

class _Neutrality extends StatelessWidget {
  const _Neutrality();

  @override
  Widget build(BuildContext context) => const Text(
    "Mêmes questions pour tout le monde, groupes interrogés à tour de rôle, réponses tirées des décomptes officiels de l'Assemblée. Aucun point : ce n'est pas un pronostic.",
    textAlign: TextAlign.center,
    style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.quiz, required this.current, required this.total});

  final QuizDto quiz;
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageTitle("Qui a voté ?"),
        const SizedBox(height: AppSpacing.sm),
        const Text("Cinq questions par jour sur les votes de l'Assemblée.", style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.bodyLarge)),
        const SizedBox(height: AppSpacing.md),
        if (quiz.signedIn)
          SectionCard(
            child: Row(
              children: [
                const Icon(Icons.local_fire_department_rounded, color: AppColors.gold),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(quiz.streak == 0 ? "Pas encore de série" : "Série de ${quiz.streak} ${quiz.streak == 1 ? "jour" : "jours"}", style: AppTextStyles.bodyLargeStrong.copyWith(color: AppColors.gold))),
                if (quiz.bestStreak > 0) Text("Record : ${quiz.bestStreak}", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            SectionLabel(current > total ? "BILAN DU JOUR" : "QUESTION $current SUR $total"),
            const Spacer(),
            for (var i = 1; i <= total; i++)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: i < current ? AppColors.brass : (i == current ? AppColors.textPrimary : AppColors.surfaceBorder)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question});

  final QuizQuestionDto question;

  @override
  Widget build(BuildContext context) {
    return OrnateFrame(
      strong: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.card), color: AppColors.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel("VOTE SUR L'ENSEMBLE DU TEXTE · ${lawDayLabel(question.date).toUpperCase()}"),
            const SizedBox(height: AppSpacing.sm),
            Text(question.lawName, style: AppTextStyles.bodyLargeStrong),
            const SizedBox(height: AppSpacing.md),
            const Text("Comment le groupe", style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(question.groupName, style: AppTextStyles.sectionTitle),
            const SizedBox(height: 2),
            const Text("a-t-il voté ?", style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.label, required this.kind, required this.enabled, required this.onTap});

  final String label;
  final SeatKind kind;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.card), border: Border.all(color: AppColors.surfaceBorderHighlight)),
              child: Row(
                children: [
                  SeatGlyph(kind, size: 16),
                  const SizedBox(width: AppSpacing.md),
                  Text(label, style: AppTextStyles.bodyLargeStrong.copyWith(color: enabled ? AppColors.textPrimary : AppColors.textTertiary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La correction : bonne ou mauvaise réponse, ce que le groupe a vraiment voté avec ses chiffres, et la source.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final QuizAnswerResultDto result;

  @override
  Widget build(BuildContext context) {
    final group = result.group;
    final answer = positionLabel(result.answer);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(result.correct ? Icons.check_circle_rounded : Icons.cancel_rounded, color: result.correct ? AppColors.win : AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text(result.correct ? "Bonne réponse" : "Pas cette fois", style: AppTextStyles.bodyLargeStrong),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text("${group.name} a voté : $answer", style: AppTextStyles.bodyStrong),
          const SizedBox(height: 4),
          OutcomeBar(pour: group.pour.toInt(), contre: group.contre.toInt(), abst: group.abst.toInt()),
          const SizedBox(height: 4),
          Text("${group.pour.toInt()} pour · ${group.contre.toInt()} contre · ${group.abst.toInt()} abstention${group.abst.toInt() > 1 ? "s" : ""}", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
          const SizedBox(height: AppSpacing.sm),
          Text("Sur l'ensemble : ${result.vote.sentence}", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            children: [
              TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: result.eventId))), child: const Text("Voir le vote")),
              TextButton(onPressed: () => launchUrl(Uri.parse(result.sourceUrl), mode: LaunchMode.externalApplication), child: const Text("Source officielle")),
            ],
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.quiz, required this.questions, required this.results, required this.header});

  final QuizDto quiz;
  final List<QuizQuestionDto> questions;
  final Map<String, QuizAnswerResultDto> results;
  final Widget header;

  bool? _correct(QuizQuestionDto q) => results[q.id]?.correct ?? q.myCorrect;

  @override
  Widget build(BuildContext context) {
    final good = questions.where((q) => _correct(q) == true).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        header,
        const SizedBox(height: AppSpacing.md),
        OrnateFrame(
          strong: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.card), color: AppColors.surface),
            child: Column(
              children: [
                Text("$good / ${questions.length}", style: AppTextStyles.pageTitle),
                const SizedBox(height: AppSpacing.sm),
                Text(good == 1 ? "bonne réponse aujourd'hui" : "bonnes réponses aujourd'hui", style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.sm),
                const Text("Cinq nouvelles questions demain.", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (final (i, q) in questions.indexed) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.surfaceBorder),
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: q.eventId))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
                    child: Row(
                      children: [
                        Icon(_correct(q) == true ? Icons.check_circle_rounded : Icons.cancel_rounded, color: _correct(q) == true ? AppColors.win : AppColors.textTertiary),
                        const SizedBox(width: AppSpacing.sm + 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(q.groupName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyStrong),
                              Text(q.lawName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!quiz.signedIn) ...[
          const SizedBox(height: AppSpacing.md),
          const Text("Connecte-toi pour garder ta série de jours.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
        ],
        const SizedBox(height: AppSpacing.lg),
        const _Neutrality(),
      ],
    );
  }
}
