import "package:built_collection/built_collection.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/text_x.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/competitions/competitions_data.dart";
import "package:mobile/features/competitions/competitions_screen.dart";
import "package:mobile/features/home/home_screen.dart" show favoriteCategoryProvider;
import "package:news_api_client/news_api_client.dart";
import "../competitions_test_helpers.dart";

CatalogDto _catalog({bool championsLive = false, bool eteLive = false}) => CatalogDto((b) => b
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
                CatalogChildDto((k) => k..major = true..live = championsLive
                  ..id = "champions"
                  ..name = "Champions 2026"),
                CatalogChildDto((k) => k..major = false..live = eteLive
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

  Future<void> pumpScreen(WidgetTester tester, {List<String> favorites = const [], List<FavoriteCompetitionDto> favoriteCompetitions = const [], bool championsLive = false, bool eteLive = false, CompetitionResponseDto? championsDetail}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith((ref) async => _catalog(championsLive: championsLive, eteLive: eteLive)),
          favoriteCategoryProvider.overrideWithValue(null),
          if (championsDetail != null) competitionDetailProvider("champions").overrideWith((ref) async => championsDetail),
          overrideFavoriteGamesWith(favorites),
          overrideFavoriteCompetitionsWith(favoriteCompetitions),
        ],
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

  testWidgets("sans série en cours, pas de section « En cours »", (tester) async {
    await pumpScreen(tester);
    expect(find.text("EN COURS"), findsNothing);
  });

  testWidgets("une grande série en cours est dans « En cours », repliée d'office", (tester) async {
    await pumpScreen(tester, championsLive: true);
    expect(find.text("EN COURS (1)"), findsOneWidget);
    // Repliée : la carte n'est pas affichée tant qu'on n'a pas touché la section.
    expect(find.text("Champions 2026"), findsNothing);

    await tester.tap(find.text("EN COURS (1)"));
    await tester.pumpAndSettle();
    expect(find.text("Champions 2026"), findsOneWidget);
    expect(find.text("VCT · Valorant"), findsOneWidget);
  });

  testWidgets("une série en cours qui n'est pas un grand rendez-vous reste hors de « En cours »", (tester) async {
    await pumpScreen(tester, eteLive: true);
    expect(find.textContaining("EN COURS"), findsNothing);
  });

  testWidgets("la carte d'une grande série donne ses dates et sa description, avec sa source", (tester) async {
    await pumpScreen(
      tester,
      championsLive: true,
      championsDetail: CompetitionResponseDto((c) => c
        ..id = "champions"
        ..name = "Champions 2026"
        ..kind = "serie"
        ..startsAt = "2026-09-24T10:00:00.000Z"
        ..endsAt = "2026-10-18T18:00:00.000Z"
        ..sourceUpdatedAt = "2026-10-01T00:00:00.000Z"
        ..context.replace(CompetitionContextDto((x) => x
          ..text = "Compétition organisée par Riot Games, à Shanghai."
          ..source_ = "Liquipedia"
          ..license = "CC-BY-SA"))),
    );
    await tester.tap(find.text("EN COURS (1)"));
    await tester.pumpAndSettle();
    expect(find.text("24 sept. – 18 oct. 2026"), findsOneWidget);
    expect(find.text("Compétition organisée par Riot Games, à Shanghai."), findsOneWidget);
    expect(find.text("Source : Liquipedia (CC-BY-SA)"), findsOneWidget);
  });

  test("formatDateRange : un même mois, deux mois, deux années, sans fin, sans début", () {
    expect(formatDateRange("2026-10-24T10:00:00.000Z", "2026-10-31T10:00:00.000Z"), "24 – 31 oct. 2026");
    expect(formatDateRange("2026-09-24T10:00:00.000Z", "2026-10-18T10:00:00.000Z"), "24 sept. – 18 oct. 2026");
    expect(formatDateRange("2026-12-28T10:00:00.000Z", "2027-01-04T10:00:00.000Z"), "28 déc. 2026 – 4 janv. 2027");
    expect(formatDateRange("2026-10-24T10:00:00.000Z", null), "À partir du 24 oct. 2026");
    expect(formatDateRange(null, null), isNull);
  });

  testWidgets("une compétition favorite apparaît dans Favoris", (tester) async {
    await pumpScreen(tester, favoriteCompetitions: [
      FavoriteCompetitionDto((f) => f
        ..id = "champions"
        ..name = "Champions 2026"),
    ]);
    expect(find.text("FAVORIS"), findsOneWidget);
    expect(find.widgetWithText(ActionChip, "Champions 2026"), findsOneWidget);
  });

  test("liveSeries ne garde que les séries en cours, avec leur ligue et leur jeu", () {
    expect(liveSeries(_catalog()), isEmpty);
    // Une série en cours qui n'est pas un grand rendez-vous n'en fait pas partie.
    expect(liveSeries(_catalog(eteLive: true)), isEmpty);
    final live = liveSeries(_catalog(championsLive: true)).single;
    expect(live.serie.id, "champions");
    expect(live.league.name, "VCT");
    expect(live.game.name, "Valorant");
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
