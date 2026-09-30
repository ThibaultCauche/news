import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/learn/learn_screen.dart";

Widget _app(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(container: container, child: MaterialApp(home: Scaffold(body: home)));

// `rootBundle` ne se résout pas sous l'horloge factice des tests de widgets.
Future<(ProviderContainer, LearnGuide)> _load(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final guide = (await tester.runAsync(() => container.read(learnGuideProvider("valorant").future)))!;
  return (container, guide);
}

void main() {
  testWidgets("les tutos Valorant sont complets (aucun texte vide)", (tester) async {
    final (_, guide) = await _load(tester);

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
    }
  });

  testWidgets("la liste ouvre un article sans bouton « Toutes les règles »", (tester) async {
    final (container, _) = await _load(tester);
    await tester.pumpWidget(_app(container, const LearnTab(game: "valorant")));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Les 4 rôles"));
    await tester.pumpAndSettle();
    expect(find.text("L'ESSENTIEL"), findsOneWidget);
    expect(find.text("Quelques agents"), findsOneWidget);
    expect(find.textContaining("Toutes les règles"), findsNothing);
  });

  testWidgets("depuis un « ? », le bouton mène à la liste des règles", (tester) async {
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
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (container, guide) = await _load(tester);
    for (final a in guide.articles) {
      await tester.pumpWidget(_app(container, LearnArticleScreen(game: "valorant", articleId: a.id, showAllRules: true)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: a.id);
    }
  });
}
