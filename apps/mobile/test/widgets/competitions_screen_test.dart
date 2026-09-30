import "package:built_collection/built_collection.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/text_x.dart";
import "package:mobile/features/competitions/competitions_data.dart";
import "package:mobile/features/competitions/competitions_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../competitions_test_helpers.dart";

CatalogDto _catalog() => CatalogDto((b) => b
  ..categories = ListBuilder<CatalogCategoryDto>([
    CatalogCategoryDto((c) => c
      ..slug = "esport"
      ..name = "Esport"
      ..games = ListBuilder<CatalogGameDto>([
        CatalogGameDto((g) => g
          ..slug = "valorant"
          ..name = "Valorant"
          ..leagues = ListBuilder<CatalogLeagueDto>([
            CatalogLeagueDto((l) => l
              ..live = false
              ..id = "vct"
              ..name = "VCT"
              ..children = ListBuilder<CatalogChildDto>([
                CatalogChildDto((k) => k
                  ..id = "champions"
                  ..name = "Champions 2026"),
                CatalogChildDto((k) => k
                  ..id = "ete"
                  ..name = "Événement Été 2026"),
              ])),
          ])),
      ])),
  ]));

void main() {
  test("normalizeSearch ignore la casse et les accents", () {
    expect(normalizeSearch("Événement Été"), "evenement ete");
    expect(normalizeSearch("ÇA"), "ca");
  });

  test("searchCatalog trouve un jeu, une ligue et une série sans tenir compte des accents", () {
    final catalog = _catalog();
    expect(searchCatalog(catalog, "VALO").map((r) => r.kind), [SearchKind.game]);
    expect(searchCatalog(catalog, "vct").map((r) => r.kind), [SearchKind.league]);
    final byAccent = searchCatalog(catalog, "evenement ete");
    expect(byAccent.single.kind, SearchKind.serie);
    expect(byAccent.single.competitionId, "ete");
    expect(searchCatalog(catalog, "  "), isEmpty);
    expect(searchCatalog(catalog, "inexistant"), isEmpty);
  });

  Future<void> pumpScreen(WidgetTester tester, {List<String> favorites = const []}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogProvider.overrideWith((ref) async => _catalog()), overrideFavoriteGamesWith(favorites)],
        child: const MaterialApp(home: Scaffold(body: CompetitionsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets("n'affiche que les catégories du catalogue et déroule les jeux", (tester) async {
    await pumpScreen(tester);
    expect(find.text("Esport"), findsOneWidget);
    expect(find.text("Sport"), findsNothing);
    expect(find.text("FAVORIS"), findsNothing);

    await tester.tap(find.text("Esport"));
    await tester.pumpAndSettle();
    expect(find.text("Valorant"), findsOneWidget);
  });

  testWidgets("les jeux favoris apparaissent dans le raccourci Favoris", (tester) async {
    await pumpScreen(tester, favorites: ["valorant"]);
    expect(find.text("FAVORIS"), findsOneWidget);
    expect(find.widgetWithText(ActionChip, "Valorant"), findsOneWidget);
  });

  testWidgets("la recherche filtre le catalogue", (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), "evenement");
    await tester.pump();
    expect(find.text("Événement Été 2026"), findsOneWidget);
    expect(find.text("Champions 2026"), findsNothing);
    expect(find.text("Esport"), findsNothing);

    await tester.enterText(find.byType(TextField), "zzz");
    await tester.pump();
    expect(find.text("Aucun résultat."), findsOneWidget);
  });
}
