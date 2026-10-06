import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/agenda/agenda_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";
import "../settings_test_helpers.dart";

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _mondayOf(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // N'importe quelle fenêtre demandée : seule la navigation entre
        // semaines est testée ici, pas le contenu de la liste (J8).
        agendaProvider.overrideWith((ref, query) async => AgendaResponseDto((b) => b..sourceUpdatedAt = "2026-09-27T00:00:00Z")),
        userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
          ..spoilerFree = false
          ..morningDigest = false)),
        overrideCompactEventCardsWith(false),
        await overrideAuthStoreForTest(),
      ],
      child: const MaterialApp(home: Scaffold(body: AgendaScreen())),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting("fr_FR");
  });

  testWidgets("flèche suivante avance la semaine affichée de 7 jours", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    final today = _dateOnly(DateTime.now());
    final nextMonday = _mondayOf(today).add(const Duration(days: 7));

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();

    expect(find.text("${nextMonday.day}"), findsOneWidget);
  });

  testWidgets("flèche précédente permet de revenir avant aujourd'hui", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    final today = _dateOnly(DateTime.now());
    final previousMonday = _mondayOf(today).subtract(const Duration(days: 7));

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();

    expect(find.text("${previousMonday.day}"), findsOneWidget);
  });

  testWidgets("la flèche suivante se désactive à la borne +14 jours", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    final nextButton = find.widgetWithIcon(IconButton, Icons.chevron_right_rounded);

    // Au plus 4 semaines suffisent à couvrir toute fenêtre ±14 jours.
    for (var i = 0; i < 4; i++) {
      if (tester.widget<IconButton>(nextButton).onPressed == null) break;
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
    }

    expect(tester.widget<IconButton>(nextButton).onPressed, isNull);
  });

  Future<List<AgendaQuery>> pumpRecording(WidgetTester tester, {List<EventSummaryDto> events = const []}) async {
    final queries = <AgendaQuery>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          overrideSignedInForTest(),
          overrideFollowsWith(const []),
          agendaProvider.overrideWith((ref, query) async {
            queries.add(query);
            return AgendaResponseDto((b) => b
              ..sourceUpdatedAt = "2026-09-27T00:00:00Z"
              ..events.addAll(events));
          }),
          userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
            ..spoilerFree = false
            ..morningDigest = false)),
          overrideCompactEventCardsWith(false),
          await overrideAuthStoreForTest(),
        ],
        child: MaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: AgendaScreen())),
      ),
    );
    await tester.pumpAndSettle();
    return queries;
  }

  testWidgets("catégories à sélection multiple : icône seule inactive, nom visible une fois cochée (J22, #D3 #D5)", (tester) async {
    final queries = await pumpRecording(tester);
    expect(queries.last.category, isNull);
    expect(find.text("Sport"), findsNothing); // icône seule

    await tester.tap(find.byIcon(Icons.sports_soccer_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.sports_esports_rounded));
    await tester.pumpAndSettle();

    expect(find.text("Sport"), findsOneWidget);
    expect(find.text("E-sport"), findsOneWidget);
    expect(queries.last.category, "esport,sport");

    await tester.tap(find.byIcon(Icons.sports_soccer_rounded));
    await tester.pumpAndSettle();
    expect(queries.last.category, "esport");
  });

  testWidgets("Mes suivis / Tout : « Tout » sans suivi, la bascule change la requête (J22, #D1)", (tester) async {
    final queries = await pumpRecording(tester);
    expect(queries.last.mine, isFalse);

    await tester.tap(find.text("Mes suivis"));
    await tester.pumpAndSettle();
    expect(queries.last.mine, isTrue);
    expect(find.text("Rien dans tes suivis sur cette période."), findsOneWidget);

    await tester.tap(find.text("Voir tout l'agenda"));
    await tester.pumpAndSettle();
    expect(queries.last.mine, isFalse);
  });

  testWidgets("le calendrier s'ouvre sur le mois du jour et recentre la fenêtre sur la date choisie (J22, #D4)", (tester) async {
    final queries = await pumpRecording(tester);
    final before = queries.last.from;

    await tester.tap(find.byTooltip("Choisir une date"));
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendarSheet), findsOneWidget);

    // Un mois plus loin : le 1er du mois devient le centre de la fenêtre.
    await tester.tap(find.byTooltip("Mois suivant"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("1").last);
    await tester.pumpAndSettle();

    expect(find.byType(MonthCalendarSheet), findsNothing);
    expect(queries.last.from, isNot(before));
    final now = DateTime.now();
    final firstOfNextMonth = DateTime(now.year, now.month + 1, 1);
    expect(queries.last.from, firstOfNextMonth.subtract(const Duration(days: 14)));
  });

  testWidgets("« Aujourd'hui » n'apparaît qu'une fois éloigné de la date du jour, et y ramène (J22)", (tester) async {
    final queries = await pumpRecording(tester);
    expect(find.text("Aujourd'hui"), findsNothing);

    await tester.tap(find.byTooltip("Choisir une date"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Mois suivant"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("1").last);
    await tester.pumpAndSettle();
    expect(find.text("Aujourd'hui"), findsOneWidget);

    await tester.tap(find.text("Aujourd'hui"));
    await tester.pumpAndSettle();
    expect(find.text("Aujourd'hui"), findsNothing);
    final today = DateTime.now();
    expect(queries.last.from, DateTime(today.year, today.month, today.day).subtract(const Duration(days: 14)));
  });

  testWidgets("un balayage horizontal change de jour (J22)", (tester) async {
    await pumpRecording(tester);
    await tester.fling(find.text("Rien à afficher pour l'instant."), const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    // Le jour sélectionné n'est plus aujourd'hui : le raccourci est là.
    expect(find.text("Aujourd'hui"), findsOneWidget);
  });

  test("points du calendrier : seulement les jours avec un match qui a des équipes", () {
    EventSummaryDto event(String id, DateTime at, {bool teams = true}) => EventSummaryDto((e) => e
      ..id = id
      ..kind = "match"
      ..name = id
      ..status = "scheduled"
      ..startsAt = at.toUtc().toIso8601String()
      ..importance = 1
      ..competition.replace(CompetitionRefDto((c) => c
        ..id = "c"
        ..name = "c"))
      ..participants.addAll(teams
          ? [EventParticipantDto((p) => p
              ..entityId = "a"
              ..name = "A")]
          : <EventParticipantDto>[]));
    final days = daysWithMatches([event("1", DateTime(2026, 10, 7, 12)), event("2", DateTime(2026, 10, 9, 12), teams: false)]);
    expect(days, {DateTime(2026, 10, 7)});
  });
}
