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
import "package:mobile/widgets/competition_follow_button.dart";
import "package:news_api_client/news_api_client.dart";
import "../competitions_test_helpers.dart";
import "../follows_test_helpers.dart";
import "../settings_test_helpers.dart";

final _vct = CatalogLeagueDto((l) => l
  ..live = false
  ..id = "vct"
  ..name = "VCT"
  ..families = ListBuilder<CatalogFamilyDto>([
    CatalogFamilyDto((f) => f
      ..id = "fam-champions"
      ..name = "Champions"),
    CatalogFamilyDto((f) => f
      ..id = "fam-masters"
      ..name = "Masters"),
  ])
  ..children = ListBuilder<CatalogChildDto>([
    CatalogChildDto((k) => k
      ..id = "champions"
      ..name = "Champions 2026"
      ..familyId = "fam-champions"),
    CatalogChildDto((k) => k
      ..id = "masters-london"
      ..name = "Masters London 2026"
      ..familyId = "fam-masters"),
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

FollowStateDto _follow(String targetId, String name, {String targetType = "competition", bool muted = false}) => FollowStateDto((b) => b
  ..id = "sub-$targetId"
  ..targetType = targetType
  ..targetId = targetId
  ..level = "all"
  ..notifyReminder = true
  ..notifyStart = true
  ..notifyResult = true
  ..muted = muted
  ..name = name);

void main() {
  test("findLeague retrouve une ligue du catalogue, pas une série", () {
    expect(findLeague(_catalog(), "vct")?.league.name, "VCT");
    expect(findLeague(_catalog(), "vct")?.game.slug, "valorant");
    expect(findLeague(_catalog(), "champions"), isNull);
    expect(findLeague(null, "vct"), isNull);
  });

  test("findSerie et findLeagueOfFamily", () {
    expect(findSerie(_catalog(), "champions")?.serie.familyId, "fam-champions");
    expect(findSerie(_catalog(), "vct"), isNull);
    expect(findLeagueOfFamily(_catalog(), "fam-masters")?.league.id, "vct");
    expect(findLeagueOfFamily(_catalog(), "inconnue"), isNull);
  });

  Future<void> pumpLeague(WidgetTester tester, List<FollowStateDto> follows, List<String> calls) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
        overrideSignedInForTest(),overrideFollowsRecording(follows, calls)],
        child: MaterialApp(home: LeagueScreen(league: _vct, game: _valorant)),
      ),
    );
    await tester.pump();
  }

  testWidgets("page ligue : nom, compétitions, et la phrase qui dit ce que suit « Suivre »", (tester) async {
    await pumpLeague(tester, const [], []);
    expect(find.text("VCT"), findsOneWidget);
    expect(find.text("Ligue · Valorant"), findsOneWidget);
    expect(find.text("Champions 2026"), findsOneWidget);
    expect(find.textContaining("actuelles et futures"), findsOneWidget);
  });

  testWidgets("« Suivre » ouvre le choix : toute la ligue ou des familles sans l'année ; Valider suit directement", (tester) async {
    final calls = <String>[];
    await pumpLeague(tester, const [], calls);
    await tester.tap(find.text("Suivre"));
    await tester.pumpAndSettle();

    expect(find.text("Suivre dans VCT"), findsOneWidget);
    expect(find.text("Toute la ligue VCT"), findsOneWidget);
    expect(find.text("Champions"), findsOneWidget); // sans l'année
    expect(find.text("Masters"), findsOneWidget);
    expect(find.text("Champions 2026"), findsWidgets); // la liste de la page derrière

    await tester.tap(find.text("Champions"));
    await tester.tap(find.text("Masters"));
    await tester.pump();
    await tester.tap(find.text("Valider"));
    await tester.pumpAndSettle();

    expect(calls, ["follow competition_family fam-champions", "follow competition_family fam-masters"]);
    expect(find.text("Suivre dans VCT"), findsNothing); // fenêtre fermée
    expect(find.text("Suivi"), findsOneWidget);
  });

  testWidgets("« Toute la ligue » suit la ligue et rend les familles redondantes", (tester) async {
    final calls = <String>[];
    await pumpLeague(tester, [_follow("fam-champions", "Champions", targetType: "competition_family")], calls);
    await tester.tap(find.text("Suivi"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Toute la ligue VCT"));
    await tester.pump();
    await tester.tap(find.text("Valider"));
    await tester.pumpAndSettle();

    expect(calls, ["follow competition vct", "unfollow competition_family fam-champions"]);
  });

  testWidgets("décocher tout et valider se désabonne, et retire les sourdines devenues sans objet", (tester) async {
    final calls = <String>[];
    await pumpLeague(
      tester,
      [_follow("vct", "VCT"), _follow("champions", "Champions 2026", muted: true)],
      calls,
    );
    await tester.tap(find.text("Suivi"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Toute la ligue VCT"));
    await tester.pump();
    await tester.tap(find.text("Valider"));
    await tester.pumpAndSettle();

    expect(calls, ["unfollow competition vct", "unfollow competition champions"]);
  });

  Future<void> pumpSeriePage(WidgetTester tester, List<FollowStateDto> follows, List<String> calls) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
        overrideSignedInForTest(),overrideFollowsRecording(follows, calls), catalogProvider.overrideWith((ref) async => _catalog())],
        child: MaterialApp(
          home: Scaffold(appBar: AppBar(actions: const [CompetitionFollowButton(competitionId: "champions", name: "Champions 2026")])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets("série couverte par la ligue suivie : « Suivi via VCT », puis sourdine sur celle-ci seulement", (tester) async {
    final calls = <String>[];
    await pumpSeriePage(tester, [_follow("vct", "VCT")], calls);
    expect(find.text("Suivi via VCT"), findsOneWidget);

    await tester.tap(find.text("Suivi via VCT"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Ne pas m'alerter"));
    await tester.pumpAndSettle();

    expect(calls, ["mute competition champions"]);
    expect(find.text("Réactiver les alertes"), findsOneWidget);

    await tester.tap(find.text("Réactiver les alertes"));
    await tester.pump();
    expect(calls, ["mute competition champions", "unfollow competition champions"]);
  });

  testWidgets("série couverte par sa famille suivie : « Suivi via Champions »", (tester) async {
    await pumpSeriePage(tester, [_follow("fam-champions", "Champions", targetType: "competition_family")], []);
    expect(find.text("Suivi via Champions"), findsOneWidget);
  });

  testWidgets("série non couverte : « Suivre » abonne directement la série", (tester) async {
    final calls = <String>[];
    await pumpSeriePage(tester, const [], calls);
    await tester.tap(find.text("Suivre"));
    await tester.pump();
    expect(calls, ["follow competition champions"]);
  });

  testWidgets("recherche : toucher une ligue ouvre sa page", (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
        overrideSignedInForTest(),
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
        overrideSignedInForTest(),
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

  testWidgets("Suivis : une famille suivie s'affiche « Toutes les éditions » et mène à sa ligue", (tester) async {
    await pumpFollows(tester, [_follow("fam-champions", "Champions", targetType: "competition_family")]);
    expect(find.text("Champions"), findsOneWidget);
    expect(find.text("Toutes les éditions"), findsOneWidget);
    await tester.tap(find.text("Champions"));
    await tester.pumpAndSettle();
    expect(find.byType(LeagueScreen), findsOneWidget);
  });

  testWidgets("Suivis : une sourdine n'est pas un suivi, pas de carte", (tester) async {
    await pumpFollows(tester, [_follow("vct", "VCT"), _follow("champions", "Champions 2026", muted: true)]);
    expect(find.text("VCT"), findsOneWidget);
    expect(find.text("Champions 2026"), findsNothing);
  });

  testWidgets("Suivis : une série suivie mène toujours à la page compétition", (tester) async {
    await pumpFollows(tester, [_follow("champions", "Champions 2026")]);
    await tester.tap(find.text("Champions 2026"));
    await tester.pumpAndSettle();
    expect(find.byType(BracketScreen), findsOneWidget);
    expect(find.byType(LeagueScreen), findsNothing);
  });
}
