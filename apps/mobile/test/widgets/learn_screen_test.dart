import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/auth/account.dart";
import "package:mobile/features/learn/learn_screen.dart";
import "package:shared_preferences/shared_preferences.dart";

const _guides = ["valorant", "app", "valorant-competitions"];

class _Guest extends SignedInNotifier {
  @override
  bool build() => false;
}

Widget _app(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(container: container, child: MaterialApp(home: Scaffold(body: home)));

// `rootBundle` ne se résout pas sous l'horloge factice des tests de widgets.
Future<(ProviderContainer, LearnGuide)> _load(WidgetTester tester, [String game = "valorant"]) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(overrides: [signedInProvider.overrideWith(_Guest.new)]);
  addTearDown(container.dispose);
  final guide = (await tester.runAsync(() => container.read(learnGuideProvider(game).future)))!;
  return (container, guide);
}

void main() {
  testWidgets("les tutos sont complets (aucun texte vide, quiz cohérents)", (tester) async {
    for (final game in _guides) {
      final (_, guide) = await _load(tester, game);

      expect(guide.name, isNotEmpty);
      expect(guide.articles, isNotEmpty);
      expect({for (final a in guide.articles) a.id}.length, guide.articles.length);
      for (final a in guide.articles) {
        expect(a.title.trim(), isNotEmpty);
        expect(a.summary.trim(), isNotEmpty);
        expect(a.essential.trim(), isNotEmpty);
        expect(a.details, isNotEmpty);
        for (final d in a.details) {
          expect(d.title.trim(), isNotEmpty);
          expect(d.body != null || d.visual != null, isTrue, reason: "${a.id} / ${d.title} est vide");
        }
        for (final q in a.quiz) {
          expect(q.choices.length, greaterThan(1), reason: a.id);
          expect(q.answer, inInclusiveRange(0, q.choices.length - 1), reason: "${a.id} : bonne réponse hors choix");
        }
      }
    }
  });

  testWidgets("chaque mot [[terme]] des tutos existe dans le glossaire (seed)", (tester) async {
    final seed = File("../../packages/db/prisma/seed.ts").readAsStringSync().toLowerCase();
    final marker = RegExp(r"\[\[(.+?)\]\]");
    for (final game in _guides) {
      final (_, guide) = await _load(tester, game);
      for (final a in guide.articles) {
        final texts = [a.essential, for (final d in a.details) d.body ?? ""];
        for (final text in texts) {
          for (final m in marker.allMatches(text)) {
            expect(seed.contains('term: "${m.group(1)!.toLowerCase()}"'), isTrue, reason: "« ${m.group(1)} » (${a.id}) absent du glossaire");
          }
        }
      }
    }
  });

  testWidgets("la liste ouvre un article, le marque lu et n'affiche pas « Toutes les règles »", (tester) async {
    final (container, _) = await _load(tester);
    await tester.pumpWidget(_app(container, const LearnTab(game: "valorant")));
    await tester.pumpAndSettle();
    expect(find.textContaining("0/7 lus"), findsOneWidget);

    await tester.tap(find.text("Les 4 rôles"));
    await tester.pumpAndSettle();
    expect(find.text("L'ESSENTIEL"), findsOneWidget);
    expect(find.text("Quelques agents"), findsOneWidget);
    expect(find.textContaining("Toutes les règles"), findsNothing);
    expect(container.read(learnReadProvider).value!.read, contains("valorant/roles"));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining("1/7 lus"), findsOneWidget);
  });

  testWidgets("quiz : la réponse affiche l'explication", (tester) async {
    final (container, _) = await _load(tester);
    await tester.pumpWidget(_app(container, const LearnArticleScreen(game: "valorant", articleId: "cartes")));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text("TESTE-TOI"), 200);
    await tester.scrollUntilVisible(find.text("4"), 200);
    await tester.tap(find.text("4"));
    await tester.pumpAndSettle();
    expect(find.textContaining("Pas tout à fait"), findsOneWidget);
    expect(container.read(learnReadProvider).value!.passed, isNot(contains("valorant/cartes")));
  });

  testWidgets("quiz : toutes les réponses justes marquent le quiz réussi", (tester) async {
    final (container, _) = await _load(tester);
    await tester.pumpWidget(_app(container, const LearnArticleScreen(game: "valorant", articleId: "cartes")));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text("TESTE-TOI"), 200);
    await tester.scrollUntilVisible(find.text("2"), 200);
    await tester.tap(find.text("2"));
    await tester.pumpAndSettle();
    expect(find.textContaining("Bravo"), findsOneWidget);
    expect(container.read(learnReadProvider).value!.passed, contains("valorant/cartes"));
  });

  testWidgets("depuis un « ? », le bouton mène à la liste du guide", (tester) async {
    final (container, _) = await _load(tester);
    await tester.pumpWidget(_app(container, const LearnArticleScreen(game: "valorant", articleId: "le-jeu", showAllRules: true)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text("Toutes les règles · Valorant"), 200);
    await tester.ensureVisible(find.text("Toutes les règles · Valorant"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Toutes les règles · Valorant"));
    await tester.pumpAndSettle();
    expect(find.text("Règles · Valorant"), findsOneWidget);
    expect(find.text("Les 4 rôles"), findsOneWidget);
  });

  testWidgets("chaque article s'affiche sans débordement sur un écran étroit (360)", (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final game in _guides) {
      final (container, guide) = await _load(tester, game);
      for (final a in guide.articles) {
        await tester.pumpWidget(_app(container, LearnArticleScreen(game: game, articleId: a.id, showAllRules: true)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: "$game/${a.id}");
      }
    }
  });

  testWidgets("les jeux avec guide sont déduits des fichiers de assets/learn", (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final games = (await tester.runAsync(() => container.read(learnGamesProvider.future)))!;

    expect(games, containsAll(["valorant", "app"]));
  });
}
