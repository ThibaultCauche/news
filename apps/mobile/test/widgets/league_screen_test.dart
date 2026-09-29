import "package:built_collection/built_collection.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/bracket/bracket_screen.dart";
import "package:mobile/features/competitions/competitions_data.dart";
import "package:mobile/features/competitions/competitions_screen.dart";
import "package:mobile/features/competitions/league_screen.dart";
import "package:mobile/features/follows/follows_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../competitions_test_helpers.dart";
import "../follows_test_helpers.dart";
import "../settings_test_helpers.dart";

final _vct = CatalogLeagueDto((l) => l
  ..id = "vct"
  ..name = "VCT"
  ..children = ListBuilder<CatalogChildDto>([
    CatalogChildDto((k) => k
      ..id = "champions"
      ..name = "Champions 2026"),
  ]));

final _valorant = CatalogGameDto((g) => g
  ..slug = "valorant"
  ..name = "Valorant"
  ..leagues = ListBuilder<CatalogLeagueDto>([_vct]));

CatalogDto _catalog() => CatalogDto((b) => b
  ..categories = ListBuilder<CatalogCategoryDto>([
    CatalogCategoryDto((c) => c
      ..slug = "esport"
      ..name = "Esport"
      ..games = ListBuilder<CatalogGameDto>([_valorant])),
  ]));

FollowStateDto _follow(String targetId, String name) => FollowStateDto((b) => b
  ..id = "sub-$targetId"
  ..targetType = "competition"
  ..targetId = targetId
  ..level = "all"
  ..notifyReminder = true
  ..notifyStart = true
  ..notifyResult = true
  ..name = name);

void main() {
  test("findLeague retrouve une ligue du catalogue, pas une série", () {
    expect(findLeague(_catalog(), "vct")?.league.name, "VCT");
    expect(findLeague(_catalog(), "vct")?.game.slug, "valorant");
    expect(findLeague(_catalog(), "champions"), isNull);
    expect(findLeague(null, "vct"), isNull);
  });

  testWidgets("page ligue : nom, compétitions et bouton Suivre qui abonne la ligue", (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [overrideFollowsRecording(const [], calls)],
        child: MaterialApp(home: LeagueScreen(league: _vct, game: _valorant)),
      ),
    );
    await tester.pump();

    expect(find.text("VCT"), findsOneWidget);
    expect(find.text("Ligue · Valorant"), findsOneWidget);
    expect(find.text("Champions 2026"), findsOneWidget);

    await tester.tap(find.text("Suivre"));
    await tester.pump();
    expect(calls, ["follow competition vct"]);
    expect(find.text("Suivi"), findsOneWidget);
    await tester.tap(find.text("Suivi"));
    await tester.pump();
    expect(calls, ["follow competition vct", "unfollow competition vct"]);
  });

  testWidgets("recherche : toucher une ligue ouvre sa page", (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith((ref) async => _catalog()),
          overrideFavoriteGamesWith(const []),
          overrideFollowsRecording(const [], []),
        ],
        child: const MaterialApp(home: Scaffold(body: CompetitionsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), "vct");
    await tester.pump();
    await tester.tap(find.text("VCT"));
    await tester.pumpAndSettle();
    expect(find.byType(LeagueScreen), findsOneWidget);
  });

  Future<void> pumpFollows(WidgetTester tester, List<FollowStateDto> follows) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          overrideFollowsRecording(follows, []),
          catalogProvider.overrideWith((ref) async => _catalog()),
          competitionDetailProvider("champions").overrideWith((ref) async => throw Exception("hors ligne")),
          overrideCompactEventCardsWith(false),
        ],
        child: const MaterialApp(home: Scaffold(body: FollowsScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("Suivis : une ligue suivie mène à sa page ligue", (tester) async {
    await pumpFollows(tester, [_follow("vct", "VCT")]);
    await tester.tap(find.text("VCT"));
    await tester.pumpAndSettle();
    expect(find.byType(LeagueScreen), findsOneWidget);
  });

  testWidgets("Suivis : une série suivie mène toujours à la page compétition", (tester) async {
    await pumpFollows(tester, [_follow("champions", "Champions 2026")]);
    await tester.tap(find.text("Champions 2026"));
    await tester.pumpAndSettle();
    expect(find.byType(BracketScreen), findsOneWidget);
    expect(find.byType(LeagueScreen), findsNothing);
  });
}
