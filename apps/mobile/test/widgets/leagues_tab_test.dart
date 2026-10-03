import "package:built_collection/built_collection.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/competitions/league_screen.dart";
import "package:mobile/features/competitions/leagues_tab.dart";
import "package:mobile/widgets/live_dot.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

CatalogLeagueDto _league(String id, String name, {bool live = false, int series = 2}) => CatalogLeagueDto((l) => l
  ..id = id
  ..name = name
  ..live = live
  ..families = ListBuilder<CatalogFamilyDto>()
  ..children = ListBuilder<CatalogChildDto>([
    for (var i = 0; i < series; i++)
      CatalogChildDto((k) => k..major = false..live = false
        ..id = "$id-$i"
        ..name = "$name $i"),
  ]));

CatalogGameDto _game(List<CatalogLeagueDto> leagues) => CatalogGameDto((g) => g
  ..slug = "valorant"
  ..name = "Valorant"
  ..leagues = ListBuilder<CatalogLeagueDto>(leagues));

void main() {
  test("sortLeagues : les ligues en cours d'abord, puis par nom", () {
    final sorted = sortLeagues([_league("b", "Monsters"), _league("c", "VCT", live: true), _league("a", "Esports World Cup")]);
    expect(sorted.map((l) => l.name), ["VCT", "Esports World Cup", "Monsters"]);
  });

  testWidgets("onglet Ligues : nom, nombre de compétitions et point rouge seulement pour une ligue en cours", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeaguesTab(game: _game([_league("vct", "VCT", live: true), _league("ewc", "Esports World Cup", series: 1)])),
        ),
      ),
    );

    expect(find.text("VCT"), findsOneWidget);
    expect(find.text("2 compétitions"), findsOneWidget);
    expect(find.text("1 compétition"), findsOneWidget);
    expect(find.text("En cours"), findsOneWidget);
    expect(find.byType(LiveDot), findsOneWidget); // un seul point : VCT est en cours, pas l'Esports World Cup
    // La ligue en cours est en premier.
    expect(tester.getTopLeft(find.text("VCT")).dy, lessThan(tester.getTopLeft(find.text("Esports World Cup")).dy));

    await tester.pumpWidget(const SizedBox()); // arrête l'animation du point
  });

  testWidgets("toucher une ligue ouvre sa page", (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [overrideFollowsRecording(const [], [])],
        child: MaterialApp(home: Scaffold(body: LeaguesTab(game: _game([_league("ewc", "Esports World Cup")])))),
      ),
    );
    await tester.tap(find.text("Esports World Cup"));
    await tester.pumpAndSettle();
    expect(find.byType(LeagueScreen), findsOneWidget);
  });

  testWidgets("aucune ligue : message", (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LeaguesTab(game: _game(const [])))));
    expect(find.text("Aucune ligue pour l'instant."), findsOneWidget);
  });
}
