import "package:built_value/json_object.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/formula1/f1_widgets.dart";
import "package:mobile/features/next_match/next_match_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

ClassificationRowDto _row(int position, String name, String code, {String? positionText, String? time, String? status, int points = 0}) => ClassificationRowDto((b) => b
  ..entityId = "d$position"
  ..position = position
  ..positionText = positionText ?? "$position"
  ..name = name
  ..code = code
  ..constructorName = "Écurie $code"
  ..time = time
  ..status = status
  ..points = points.toDouble());

EventDetailResponseDto _session({String status = "finished"}) => EventDetailResponseDto((b) => b
  ..id = "evt-race"
  ..kind = "session"
  ..name = "Course"
  ..status = status
  ..importance = 3
  ..sourceUpdatedAt = "2026-03-08T07:00:00.000Z"
  ..startsAt = "2026-03-08T04:00:00.000Z"
  ..result = JsonObject(<String, dynamic>{})
  ..competition.replace(CompetitionRefDto((c) => c
    ..id = "gp-1"
    ..name = "Australian Grand Prix"))
  ..context.replace(EventContextDto((c) => c))
  ..classification.addAll(status == "finished"
      ? [
          _row(1, "George Russell", "RUS", time: "1:23:06.801", points: 25),
          _row(2, "Kimi Antonelli", "ANT", time: "+2.974", points: 18),
          _row(3, "Charles Leclerc", "LEC", status: "+1 Lap", points: 15),
          _row(4, "Lewis Hamilton", "HAM", positionText: "R", status: "Engine"),
        ]
      : []));

Future<void> _pump(WidgetTester tester, EventDetailResponseDto event, {required bool spoilerFree}) async {
  // Écran haut : la liste ne construit que ce qui est visible, et la consigne se trouve sous l'arrivée.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eventProvider("evt-race").overrideWith((ref) async => event),
        // Tous les champs : sans eux le réglage ne se charge pas et « sans spoil » reste actif.
        userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
          ..spoilerFree = spoilerFree
          ..morningDigest = false
          ..notifyForumReplies = true
          ..notifyForumThreads = true
          ..notifyMatchReminder = true
          ..notifyMatchStart = true
          ..notifyMatchResult = true
          ..notifyQualification = true
          ..notifyPredictionReminders = true)),
        overrideFollowsWith(const []),
      ],
      child: const MaterialApp(home: NextMatchScreen(eventId: "evt-race")),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting("fr_FR"));

  testWidgets("une course terminée montre le podium et l'arrivée complète, abandon compris", (tester) async {
    await _pump(tester, _session(), spoilerFree: false);
    expect(find.text("GRAND PRIX D'AUSTRALIE"), findsOneWidget);
    expect(find.text("George Russell"), findsOneWidget);
    expect(find.text("1:23:06.801"), findsOneWidget);
    expect(find.text("+1 tour"), findsOneWidget);
    expect(find.text("Ab."), findsOneWidget);
    expect(find.text("Moteur"), findsOneWidget);
    expect(find.text("+25"), findsOneWidget);
    expect(find.textContaining("Maintiens pour révéler"), findsNothing);
  });

  testWidgets("en sans spoil, le classement est masqué jusqu'à l'appui long", (tester) async {
    await _pump(tester, _session(), spoilerFree: true);
    expect(find.text("Maintiens pour révéler le classement"), findsOneWidget);
  });

  testWidgets("une session à venir n'a pas encore de classement", (tester) async {
    await _pump(tester, _session(status: "scheduled"), spoilerFree: true);
    expect(find.text("Le classement sera publié après la session."), findsOneWidget);
    expect(find.text("George Russell"), findsNothing);
  });

  testWidgets("le classement du championnat est masqué en sans spoil, avec ses victoires sous le nom", (tester) async {
    CompetitionStandingDto row(int rank, String name, int points, int wins) => CompetitionStandingDto((b) => b
      ..entityId = "e$rank"
      ..entityName = name
      ..entityKind = "driver"
      ..rank = rank
      ..points = points.toDouble()
      ..wins = wins);
    final season = CompetitionResponseDto((b) => b
      ..id = "season"
      ..name = "Formule 1 2026"
      ..kind = "serie"
      ..sourceUpdatedAt = "2026-03-08T07:00:00.000Z"
      ..standings.addAll([row(1, "Andrea Kimi Antonelli", 320, 8), row(2, "George Russell", 236, 3)]));
    Future<void> pump(bool spoilerFree) async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          competitionDetailProvider("season").overrideWith((ref) async => season),
          userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
            ..spoilerFree = spoilerFree
            ..morningDigest = false
            ..notifyForumReplies = true
            ..notifyForumThreads = true
            ..notifyMatchReminder = true
            ..notifyMatchStart = true
            ..notifyMatchResult = true
            ..notifyQualification = true
            ..notifyPredictionReminders = true)),
        ],
        child: const MaterialApp(home: Scaffold(body: F1StandingsTab(seasonId: "season", constructors: false))),
      ));
      await tester.pumpAndSettle();
    }

    await pump(true);
    expect(find.text("Maintiens pour révéler le classement"), findsOneWidget);
    await pump(false);
    expect(find.text("Maintiens pour révéler le classement"), findsNothing);
    expect(find.text("320"), findsOneWidget);
    expect(find.text("8 victoires"), findsOneWidget);
  });

  testWidgets("la fiche d'un pilote : place au championnat, masquée en sans spoil, avec le bouton Suivre", (tester) async {
    final driver = EntityResponseDto((b) => b
      ..id = "d1"
      ..kind = "driver"
      ..name = "George Russell"
      ..shortName = "RUS"
      ..wins = 0
      ..losses = 0
      ..winStreak = 0
      ..sourceUpdatedAt = "2026-10-08T00:00:00Z"
      ..championships.add(EntityChampionshipDto((c) => c
        ..competitionId = "season"
        ..competitionName = "Formule 1 2026"
        ..rank = 2
        ..points = 236
        ..wins = 3)));
    Future<void> pump(bool hidden) async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [overrideFollowsWith(const [])],
        child: MaterialApp(home: Scaffold(body: ChampionshipEntityBody(entity: driver, scoresHidden: hidden))),
      ));
      await tester.pumpAndSettle();
    }

    await pump(false);
    expect(find.text("George Russell"), findsOneWidget);
    expect(find.text("Pilote"), findsOneWidget);
    expect(find.text("236"), findsOneWidget);
    expect(find.text("Suivre"), findsOneWidget);
    expect(find.textContaining("résultat de ses courses"), findsOneWidget);
    await pump(true);
    expect(find.text("Maintiens pour révéler le classement"), findsOneWidget);
  });

  testWidgets("la page d'un Grand Prix montre le circuit", (tester) async {
    final gp = CompetitionResponseDto((b) => b
      ..id = "gp"
      ..name = "Singapore Grand Prix"
      ..kind = "tournament"
      ..location = "Marina Bay Street Circuit, Marina Bay"
      ..sourceUpdatedAt = "2026-10-08T00:00:00Z");
    await tester.pumpWidget(ProviderScope(
      overrides: [competitionDetailProvider("gp").overrideWith((ref) async => gp)],
      child: const MaterialApp(home: GrandPrixScreen(competitionId: "gp", title: "Grand Prix de Singapour")),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Marina Bay Street Circuit, Marina Bay"), findsOneWidget);
  });

  testWidgets("le calendrier numérote les Grands Prix et met le prochain en avant", (tester) async {
    CompetitionChildDto race(String id, String name, String status, String start) => CompetitionChildDto((b) => b
      ..id = id
      ..name = name
      ..kind = "tournament"
      ..status = status
      ..startsAt = start
      ..endsAt = start
      ..hasEvents = true);
    final season = CompetitionResponseDto((b) => b
      ..id = "season"
      ..name = "Formule 1 2026"
      ..kind = "serie"
      ..game = "formula-1"
      ..sourceUpdatedAt = "2026-03-08T07:00:00.000Z"
      ..children.addAll([
        race("a", "Australian Grand Prix", "finished", "2026-03-06T01:30:00.000Z"),
        race("b", "Chinese Grand Prix", "scheduled", "2026-03-13T03:30:00.000Z"),
      ]));
    final game = CatalogGameDto((g) => g
      ..slug = "formula-1"
      ..name = "Formule 1"
      ..leagues.add(CatalogLeagueDto((l) => l
        ..id = "league"
        ..name = "Formule 1"
        ..live = true
        ..children.add(CatalogChildDto((c) => c
          ..id = "season"
          ..name = "Formule 1 2026"
          ..live = true
          ..major = true)))));
    await tester.pumpWidget(ProviderScope(
      overrides: [competitionDetailProvider("season").overrideWith((ref) async => season)],
      child: MaterialApp(home: Scaffold(body: F1CalendarTab(seasonId: f1SeasonId(game)))),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Grand Prix d'Australie"), findsOneWidget);
    expect(find.text("Grand Prix de Chine"), findsOneWidget);
    expect(find.text("PROCHAIN"), findsOneWidget);
  });
}
