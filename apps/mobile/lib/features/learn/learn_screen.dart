import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../theme/tokens.dart";
import "../../widgets/section_label.dart";
import "../next_match/next_match_screen.dart" show StakesText;
import "learn_visuals.dart";

/// Tutos éditoriaux (J12) : un fichier `assets/learn/<jeu>.json` par jeu ou sport,
/// écrit à la main et versionné dans le dépôt, donc pas un modèle d'API (la règle 11
/// de `CLAUDE.md` ne s'applique pas). Les mots `[[terme]]` ouvrent le glossaire.
/// Ajouter un jeu = ajouter son fichier ; aucun code à toucher.
class LearnSection {
  const LearnSection({required this.title, this.body, this.visual});

  factory LearnSection.fromJson(Map<String, dynamic> json) =>
      LearnSection(title: json["title"] as String, body: json["body"] as String?, visual: json["visual"] as Object?);

  final String title;
  final String? body;
  final Object? visual;
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
  });

  factory LearnArticle.fromJson(Map<String, dynamic> json) => LearnArticle(
    id: json["id"] as String,
    title: json["title"] as String,
    summary: json["summary"] as String,
    essential: json["essential"] as String,
    icon: json["icon"] as String,
    visual: json["visual"] as Object,
    gradient: json["gradient"] as int,
    details: [for (final d in json["details"] as List) LearnSection.fromJson(d as Map<String, dynamic>)],
  );

  final String id;
  final String title;
  final String summary;
  final String essential;
  final List<LearnSection> details;
  final String icon;
  final Object visual;
  final int gradient;
}

class LearnGuide {
  const LearnGuide({required this.name, required this.articles});

  final String name;
  final List<LearnArticle> articles;
}

final learnGuideProvider = FutureProvider.family<LearnGuide, String>((ref, game) async {
  final json = jsonDecode(await rootBundle.loadString("assets/learn/$game.json")) as Map<String, dynamic>;
  return LearnGuide(
    name: json["name"] as String,
    articles: [for (final a in json["articles"] as List) LearnArticle.fromJson(a as Map<String, dynamic>)],
  );
});

/// Onglet « Apprendre » de la page jeu.
class LearnTab extends ConsumerWidget {
  const LearnTab({super.key, required this.game});

  final String game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(learnGuideProvider(game))) {
      AsyncData(:final value) => ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
        children: [
          for (final article in value.articles)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                leading: LearnIconTile(icon: learnIcons[article.icon] ?? Icons.school_rounded, gradient: article.gradient),
                title: Text(article.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(article.summary, style: const TextStyle(color: AppColors.textSecondary)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
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
/// vers tous les tutos du jeu ; depuis la liste, ce bouton n'aurait pas de sens.
void openLearnArticle(BuildContext context, {required String game, required String articleId, bool showAllRules = true}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => LearnArticleScreen(game: game, articleId: articleId, showAllRules: showAllRules)));
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
    final name = ref.watch(learnGuideProvider(game)).value?.name ?? "";
    return Scaffold(
      appBar: AppBar(title: Text("Règles · $name")),
      body: LearnTab(game: game),
    );
  }
}

class LearnArticleScreen extends ConsumerWidget {
  const LearnArticleScreen({super.key, required this.game, required this.articleId, this.showAllRules = false});

  final String game;
  final String articleId;
  final bool showAllRules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(learnGuideProvider(game)).value;
    final article = guide?.articles.where((a) => a.id == articleId).firstOrNull;
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
                if (showAllRules) ...[
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _AllRulesScreen(game: game))),
                    child: Text("Toutes les règles${guide == null ? "" : " · ${guide.name}"}"),
                  ),
                ],
              ],
            ),
    );
  }
}
