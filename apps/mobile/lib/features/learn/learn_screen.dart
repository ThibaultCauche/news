import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:url_launcher/url_launcher.dart";

import "../../core/api_providers.dart";
import "../../core/auth/account.dart";
import "../../theme/tokens.dart";
import "../../widgets/section_label.dart";
import "../next_match/next_match_screen.dart" show StakesText;
import "learn_visuals.dart";

/// Tutos éditoriaux (J12) : un fichier `assets/learn/<guide>.json` par jeu, sport ou
/// sujet (`valorant`, `app`…), écrit à la main et versionné dans le dépôt, donc pas un
/// modèle d'API (la règle 11 de `CLAUDE.md` ne s'applique pas). Les mots `[[terme]]`
/// ouvrent le glossaire. Ajouter un guide = ajouter son fichier ; aucun code à toucher.
class LearnSection {
  const LearnSection({required this.title, this.body, this.visual});

  factory LearnSection.fromJson(Map<String, dynamic> json) =>
      LearnSection(title: json["title"] as String, body: json["body"] as String?, visual: json["visual"] as Object?);

  final String title;
  final String? body;
  final Object? visual;
}

class LearnQuestion {
  const LearnQuestion({required this.question, required this.choices, required this.answer, required this.why});

  factory LearnQuestion.fromJson(Map<String, dynamic> json) => LearnQuestion(
    question: json["q"] as String,
    choices: (json["choices"] as List).cast<String>(),
    answer: json["answer"] as int,
    why: json["why"] as String,
  );

  final String question;
  final List<String> choices;
  final int answer;
  final String why;
}

class LearnArticle {
  const LearnArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.essential,
    required this.details,
    required this.icon,
    required this.visual,
    required this.gradient,
    this.quiz = const [],
    this.linkLabel,
    this.linkUrl,
  });

  factory LearnArticle.fromJson(Map<String, dynamic> json) {
    final link = json["link"] as Map<String, dynamic>?;
    return LearnArticle(
      id: json["id"] as String,
      title: json["title"] as String,
      summary: json["summary"] as String,
      essential: json["essential"] as String,
      icon: json["icon"] as String,
      visual: json["visual"] as Object,
      gradient: json["gradient"] as int,
      details: [for (final d in json["details"] as List) LearnSection.fromJson(d as Map<String, dynamic>)],
      quiz: [for (final q in (json["quiz"] as List? ?? const [])) LearnQuestion.fromJson(q as Map<String, dynamic>)],
      linkLabel: link?["label"] as String?,
      linkUrl: link?["url"] as String?,
    );
  }

  final String id;
  final String title;
  final String summary;
  final String essential;
  final List<LearnSection> details;
  final String icon;
  final Object visual;
  final int gradient;
  final List<LearnQuestion> quiz;
  final String? linkLabel;
  final String? linkUrl;
}

class LearnGuide {
  const LearnGuide({required this.name, required this.articles, this.listTitle, this.allLabel});

  final String name;
  final List<LearnArticle> articles;

  /// Titre de la liste et libellé du bouton « tout voir » : par défaut ceux d'un jeu.
  final String? listTitle;
  final String? allLabel;

  String get title => listTitle ?? "Règles · $name";
  String get allButton => allLabel ?? "Toutes les règles · $name";
}

final learnGuideProvider = FutureProvider.family<LearnGuide, String>((ref, guide) async {
  final json = jsonDecode(await rootBundle.loadString("assets/learn/$guide.json")) as Map<String, dynamic>;
  return LearnGuide(
    name: json["name"] as String,
    listTitle: json["listTitle"] as String?,
    allLabel: json["allLabel"] as String?,
    articles: [for (final a in json["articles"] as List) LearnArticle.fromJson(a as Map<String, dynamic>)],
  );
});

/// Progression dans les tutos : ouverts (`read`) et quiz réussis (`passed`), en clés `<guide>/<id>`.
class LearnProgressState {
  const LearnProgressState({this.read = const {}, this.passed = const {}});

  final Set<String> read;
  final Set<String> passed;
}

/// Gardée sur l'appareil (commodité, marche en invité et hors ligne) et, une fois connecté,
/// synchronisée avec le compte (`/v1/me/learn`) : on retrouve sa progression en changeant de
/// téléphone. Un simple compteur, sans points (la version avec points est notée dans `docs/04`).
/// Sans stockage ni réseau, tout reste « non lu » plutôt que de planter.
class LearnProgressNotifier extends AsyncNotifier<LearnProgressState> {
  static const _readKey = "learn_read";
  static const _passedKey = "learn_passed";

  MeApi get _api => ref.read(apiClientProvider).getMeApi();

  @override
  Future<LearnProgressState> build() async {
    final signedIn = ref.watch(signedInProvider);
    var read = <String>{};
    var passed = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      read = prefs.getStringList(_readKey)?.toSet() ?? {};
      passed = prefs.getStringList(_passedKey)?.toSet() ?? {};
    } catch (_) {}
    if (signedIn) {
      try {
        final remote = (await _api.meControllerGetLearn()).data!.entries;
        final remoteRead = {for (final e in remote) "${e.guide}/${e.articleId}"};
        final remotePassed = {for (final e in remote.where((e) => e.quizPassed)) "${e.guide}/${e.articleId}"};
        // Ce qui n'existe qu'ici (fait en invité ou hors ligne) remonte vers le compte.
        for (final key in read) {
          if (!remoteRead.contains(key) || (passed.contains(key) && !remotePassed.contains(key))) {
            _push(key, passed.contains(key));
          }
        }
        read = {...read, ...remoteRead};
        passed = {...passed, ...remotePassed};
      } catch (_) {}
    }
    return LearnProgressState(read: read, passed: passed);
  }

  Future<void> markRead(String guide, String id, {bool quizPassed = false}) async {
    final key = "$guide/$id";
    final current = state.value ?? const LearnProgressState();
    final isNewRead = !current.read.contains(key);
    final isNewPass = quizPassed && !current.passed.contains(key);
    if (!isNewRead && !isNewPass) return;
    final next = LearnProgressState(read: {...current.read, key}, passed: {...current.passed, if (quizPassed) key});
    state = AsyncData(next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_readKey, next.read.toList());
      await prefs.setStringList(_passedKey, next.passed.toList());
    } catch (_) {}
    if (ref.read(signedInProvider)) await _push(key, quizPassed);
  }

  Future<void> _push(String key, bool quizPassed) async {
    final slash = key.indexOf("/");
    try {
      await _api.meControllerPutLearn(
        guide: key.substring(0, slash),
        articleId: key.substring(slash + 1),
        putLearnProgressDto: PutLearnProgressDto((b) => b.quizPassed = quizPassed ? true : null),
      );
    } catch (_) {}
  }
}

final learnReadProvider = AsyncNotifierProvider<LearnProgressNotifier, LearnProgressState>(LearnProgressNotifier.new);

/// Nombre de tutos lus d'un guide, ou `null` tant que ce n'est pas chargé.
({int read, int total})? learnProgress(WidgetRef ref, String game) {
  final guide = ref.watch(learnGuideProvider(game)).value;
  final progress = ref.watch(learnReadProvider).value;
  if (guide == null || progress == null) return null;
  return (read: guide.articles.where((a) => progress.read.contains("$game/${a.id}")).length, total: guide.articles.length);
}

/// Onglet « Apprendre » de la page jeu, et liste d'un guide.
class LearnTab extends ConsumerWidget {
  const LearnTab({super.key, required this.game});

  final String game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = learnProgress(ref, game);
    final read = ref.watch(learnReadProvider).value?.read ?? const <String>{};
    return switch (ref.watch(learnGuideProvider(game))) {
      AsyncData(:final value) => ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
        children: [
          if (progress != null) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: LinearProgressIndicator(
                      value: progress.read / progress.total,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceHighlight,
                      color: AppColors.win,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text("${progress.read}/${progress.total} lus", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.label)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          for (final article in value.articles)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                leading: LearnIconTile(icon: learnIcons[article.icon] ?? Icons.school_rounded, gradient: article.gradient),
                title: Text(article.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(article.summary, style: const TextStyle(color: AppColors.textSecondary)),
                trailing: read.contains("$game/${article.id}")
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.win)
                    : const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                onTap: () => openLearnArticle(context, game: game, articleId: article.id, showAllRules: false),
              ),
            ),
        ],
      ),
      AsyncError() => const Center(child: Text("Impossible de charger les tutos.")),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// `showAllRules` : depuis un « ? » on arrive sur un seul article, avec un bouton
/// vers tous les tutos du guide ; depuis la liste, ce bouton n'aurait pas de sens.
void openLearnArticle(BuildContext context, {required String game, required String articleId, bool showAllRules = true}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => LearnArticleScreen(game: game, articleId: articleId, showAllRules: showAllRules)));
}

/// Liste complète d'un guide (depuis l'Accueil, l'onboarding ou le bouton « tout voir »).
void openLearnGuide(BuildContext context, String game) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _AllRulesScreen(game: game)));
}

/// Icône « ? » jaune à poser dans l'`AppBar` d'une page : mène droit au tuto qui l'explique.
class LearnHelpButton extends StatelessWidget {
  const LearnHelpButton({super.key, required this.articleId, this.game = "valorant"});

  final String articleId;
  final String game;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: "Comprendre",
      icon: const Icon(Icons.help_rounded, color: AppColors.gold),
      onPressed: () => openLearnArticle(context, game: game, articleId: articleId),
    );
  }
}

class _AllRulesScreen extends ConsumerWidget {
  const _AllRulesScreen({required this.game});

  final String game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(learnGuideProvider(game)).value?.title ?? "";
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: LearnTab(game: game),
    );
  }
}

class LearnArticleScreen extends ConsumerStatefulWidget {
  const LearnArticleScreen({super.key, required this.game, required this.articleId, this.showAllRules = false});

  final String game;
  final String articleId;
  final bool showAllRules;

  @override
  ConsumerState<LearnArticleScreen> createState() => _LearnArticleScreenState();
}

class _LearnArticleScreenState extends ConsumerState<LearnArticleScreen> {
  // Réponses données à ce passage (question → juste ?) : le quiz est réussi quand toutes sont justes.
  final Map<int, bool> _answers = {};

  void _onAnswered(LearnArticle article, int index, bool correct) {
    _answers[index] = correct;
    if (_answers.length == article.quiz.length && _answers.values.every((c) => c)) {
      ref.read(learnReadProvider.notifier).markRead(widget.game, widget.articleId, quizPassed: true);
    }
  }

  @override
  void initState() {
    super.initState();
    // Ouvrir un tuto le marque lu : pas de bouton à penser pour l'utilisateur.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(learnReadProvider.notifier).markRead(widget.game, widget.articleId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final guide = ref.watch(learnGuideProvider(widget.game)).value;
    final article = guide?.articles.where((a) => a.id == widget.articleId).firstOrNull;
    return Scaffold(
      appBar: AppBar(),
      body: article == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
              children: [
                LearnHero(
                  icon: learnIcons[article.icon] ?? Icons.school_rounded,
                  gradient: article.gradient,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(article.title, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(article.summary, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: AppSpacing.md),
                      LearnVisual(spec: article.visual),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionLabel("L'ESSENTIEL"),
                const SizedBox(height: AppSpacing.xs),
                StakesText(text: article.essential),
                const SizedBox(height: AppSpacing.lg),
                for (final section in article.details)
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      children: [
                        if (section.body != null) ...[StakesText(text: section.body!), const SizedBox(height: AppSpacing.sm)],
                        if (section.visual != null) LearnVisual(spec: section.visual!),
                      ],
                    ),
                  ),
                if (article.linkUrl != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: () => launchUrl(Uri.parse(article.linkUrl!), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(article.linkLabel ?? article.linkUrl!),
                  ),
                ],
                if (article.quiz.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const SectionLabel("TESTE-TOI"),
                  const SizedBox(height: AppSpacing.sm),
                  for (final (i, question) in article.quiz.indexed)
                    LearnQuiz(question: question, onAnswered: (correct) => _onAnswered(article, i, correct)),
                ],
                if (widget.showAllRules && guide != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(onPressed: () => openLearnGuide(context, widget.game), child: Text(guide.allButton)),
                ],
              ],
            ),
    );
  }
}

/// Une question à choix : après la réponse, la bonne est en vert (« validé »), une
/// mauvaise reste neutre, et l'explication s'affiche. Rien n'est enregistré.
class LearnQuiz extends StatefulWidget {
  const LearnQuiz({super.key, required this.question, this.onAnswered});

  final LearnQuestion question;
  final ValueChanged<bool>? onAnswered;

  @override
  State<LearnQuiz> createState() => _LearnQuizState();
}

class _LearnQuizState extends State<LearnQuiz> {
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.question, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            for (final (i, choice) in q.choices.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _picked == null
                        ? () {
                            setState(() => _picked = i);
                            widget.onAnswered?.call(i == q.answer);
                          }
                        : null,
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      disabledForegroundColor: _picked != null && i == q.answer ? AppColors.win : AppColors.textSecondary,
                      side: BorderSide(color: _picked != null && i == q.answer ? AppColors.win : AppColors.surfaceBorderHighlight),
                    ),
                    child: Text(choice),
                  ),
                ),
              ),
            if (_picked != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _picked == q.answer ? "Bravo ! ${q.why}" : "Pas tout à fait. ${q.why}",
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
