import "package:built_collection/built_collection.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/competitions/game_competitions_tab.dart";
import "package:news_api_client/news_api_client.dart";

CatalogChildDto _serie(String id, String name, {bool live = false, bool major = false, String? startsAt, String? endsAt, String? champion}) => CatalogChildDto((k) => k
  ..champion = champion == null
      ? null
      : (CatalogChampionDtoBuilder()
        ..name = "Équipe $champion"
        ..shortName = champion)
  ..id = id
  ..name = name
  ..live = live
  ..major = major
  ..startsAt = startsAt
  ..endsAt = endsAt);

CatalogGameDto _lol(List<CatalogChildDto> series) => CatalogGameDto((g) => g
  ..slug = "league-of-legends"
  ..name = "League of Legends"
  ..leagues = ListBuilder<CatalogLeagueDto>([
    CatalogLeagueDto((l) => l
      ..id = "worlds"
      ..name = "Worlds"
      ..live = false
      ..children = ListBuilder<CatalogChildDto>(series)
      ..families = ListBuilder<CatalogFamilyDto>()),
  ]));

// `pumpAndSettle` ne se calme jamais : le point rouge « en cours » respire sans fin.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  final now = DateTime.utc(2026, 10, 1);
  UserSettingDto settings({required bool spoilerFree}) => UserSettingDto((b) => b
    ..spoilerFree = spoilerFree
    ..morningDigest = false
    ..notifyForumReplies = false
    ..notifyForumThreads = false
    ..notifyMatchReminder = true
    ..notifyMatchStart = true
    ..notifyMatchResult = true
    ..notifyQualification = true
    ..notifyPredictionReminders = true);
  Widget app(CatalogGameDto game, {bool spoilerFree = false}) => ProviderScope(
        key: ValueKey(spoilerFree),
        overrides: [userSettingProvider.overrideWith((ref) async => settings(spoilerFree: spoilerFree))],
        child: MaterialApp(home: Scaffold(body: GameCompetitionsTab(game: game, now: now))),
      );

  testWidgets("range les séries en cours, à venir et récentes (grands rendez-vous seulement)", (tester) async {
    final game = _lol([
      _serie("msi", "MSI 2026", major: true, startsAt: "2026-06-01T00:00:00Z", endsAt: "2026-06-20T00:00:00Z"),
      _serie("lec", "LEC Summer 2026", startsAt: "2026-06-01T00:00:00Z", endsAt: "2026-08-20T00:00:00Z"),
      _serie("split", "LCK Split 2026", live: true, startsAt: "2026-09-01T00:00:00Z", endsAt: "2026-11-01T00:00:00Z"),
      _serie("worlds26", "Worlds 2026", major: true, startsAt: "2026-10-15T00:00:00Z", endsAt: "2026-11-15T00:00:00Z"),
    ]);
    await tester.pumpWidget(app(game));
    await settle(tester);

    expect(find.text("EN COURS"), findsOneWidget);
    expect(find.text("LCK Split 2026"), findsOneWidget);
    expect(find.text("À VENIR"), findsOneWidget);
    expect(find.text("Worlds 2026"), findsOneWidget);
    expect(find.text("TERMINÉES RÉCEMMENT"), findsOneWidget);
    expect(find.text("MSI 2026"), findsOneWidget);
    // Une série terminée qui n'est pas un grand rendez-vous ne remplit pas la liste.
    expect(find.text("LEC Summer 2026"), findsNothing);
  });

  testWidgets("une série terminée affiche son champion, sauf en sans spoil", (tester) async {
    final game = _lol([_serie("msi", "MSI 2026", major: true, startsAt: "2026-06-01T00:00:00Z", endsAt: "2026-06-20T00:00:00Z", champion: "GEN")]);
    await tester.pumpWidget(app(game));
    await settle(tester);
    expect(find.textContaining("Champion : GEN"), findsOneWidget);

    await tester.pumpWidget(app(game, spoilerFree: true));
    await settle(tester);
    expect(find.textContaining("Champion"), findsNothing);
  });

  testWidgets("sans aucune série : un message plutôt qu'une page vide", (tester) async {
    await tester.pumpWidget(app(_lol(const [])));
    await settle(tester);
    expect(find.text("Aucune compétition League of Legends pour l'instant."), findsOneWidget);
  });
}
