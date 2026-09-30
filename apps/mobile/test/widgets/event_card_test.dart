import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/widgets/event_card.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";
import "../settings_test_helpers.dart";

EventSummaryDto _event({
  required String status,
  String? startsAt,
  int? scoreA,
  int? scoreB,
}) {
  return EventSummaryDto(
    (b) => b
      ..id = "evt-1"
      ..kind = "match"
      ..name = "G2 Esports vs Paper Rex"
      ..status = status
      ..startsAt = startsAt
      ..bestOf = 3
      ..importance = 3
      ..competition.replace(CompetitionRefDto((c) => c
        ..id = "comp-1"
        ..name = "Champions 2026 · Playoffs"))
      ..participants.addAll([
        EventParticipantDto((p) => p
          ..entityId = "team-a"
          ..name = "G2 Esports"
          ..shortName = "G2"
          ..score = scoreA
          ..isWinner = scoreA != null && scoreB != null ? scoreA > scoreB : null),
        EventParticipantDto((p) => p
          ..entityId = "team-b"
          ..name = "Paper Rex"
          ..shortName = "PRX"
          ..score = scoreB
          ..isWinner = scoreA != null && scoreB != null ? scoreB > scoreA : null),
      ]),
  );
}

Future<void> _pump(
  WidgetTester tester,
  EventSummaryDto event, {
  bool scoresHidden = false,
  List<String>? calls,
  Object? failWith,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        overrideSignedInForTest(),
        overrideCompactEventCardsWith(false),
        overrideFollowsRecording(const [], calls ?? [], failWith: failWith),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: EventCard(event: event, scoresHidden: scoresHidden)),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting("fr_FR");
  });

  testWidgets("à venir : affiche l'heure de début, pas de score", (tester) async {
    await _pump(tester, _event(status: "scheduled", startsAt: "2026-10-18T11:55:00.000Z"));
    // Diminutif ("G2"/"PRX"), pas le nom complet (docs/02 — "le plus visuel possible").
    expect(find.textContaining("G2"), findsOneWidget);
    expect(find.text("1-0"), findsNothing);
  });

  testWidgets("à venir avec 0-0 renvoyé par l'API : pas de score affiché", (tester) async {
    await _pump(tester, _event(status: "scheduled", startsAt: "2026-10-18T11:55:00.000Z", scoreA: 0, scoreB: 0));
    expect(find.text("0"), findsNothing);
  });

  testWidgets("en direct : affiche le score par équipe sous chaque logo et le point rouge", (tester) async {
    await _pump(tester, _event(status: "live", scoreA: 1, scoreB: 0));
    expect(find.text("1"), findsOneWidget);
    expect(find.text("0"), findsOneWidget);
  });

  testWidgets("terminé : affiche le score final par équipe sous chaque logo", (tester) async {
    await _pump(tester, _event(status: "finished", scoreA: 2, scoreB: 0));
    expect(find.text("2"), findsOneWidget);
    expect(find.text("0"), findsOneWidget);
  });

  testWidgets("terminé, sans spoil activé : masque le score (écran 15, J6)", (tester) async {
    await _pump(tester, _event(status: "finished", scoreA: 2, scoreB: 0), scoresHidden: true);
    expect(find.text("2"), findsNothing);
    expect(find.text("0"), findsNothing);
    // "VS" toujours affiché entre les deux logos, quel que soit le statut.
    expect(find.text("VS"), findsOneWidget);
  });

  testWidgets("équipes inconnues : le compte à rebours s'affiche sous le nom du match", (tester) async {
    final start = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 10, seconds: 30));
    final event = _event(status: "scheduled", startsAt: start.toIso8601String()).rebuild((b) => b.participants.clear());
    await _pump(tester, event);
    await tester.pump();
    expect(find.text("G2 Esports vs Paper Rex"), findsOneWidget);
    expect(find.textContaining("05:10:", findRichText: true), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("plus de 24 h avant le match : le VS reste, sans décompte ni « dans XhYY »", (tester) async {
    final start = DateTime.now().toUtc().add(const Duration(hours: 30));
    await _pump(tester, _event(status: "scheduled", startsAt: start.toIso8601String()));
    await tester.pump();
    expect(find.text("VS"), findsOneWidget);
    expect(find.textContaining("dans "), findsNothing);
    expect(find.textContaining(":", findRichText: true), findsOneWidget); // seulement l'heure de début, pas de chrono
  });

  testWidgets("un match en direct ou terminé garde le VS, jamais de compte à rebours", (tester) async {
    await _pump(tester, _event(status: "live", scoreA: 1, scoreB: 0));
    await tester.pump();
    expect(find.text("VS"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("terminé : couronne au-dessus du vainqueur seulement, jamais si le score est masqué (J10)", (tester) async {
    await _pump(tester, _event(status: "finished", scoreA: 2, scoreB: 0));
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == "_CrownPainter"), findsOneWidget);

    await _pump(tester, _event(status: "finished", scoreA: 2, scoreB: 0), scoresHidden: true);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == "_CrownPainter"), findsNothing);

    await _pump(tester, _event(status: "live", scoreA: 1, scoreB: 0));
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == "_CrownPainter"), findsNothing);
  });

  testWidgets("reporté : affiche le statut, pas d'heure ni de score", (tester) async {
    await _pump(tester, _event(status: "postponed"));
    expect(find.text("Reporté"), findsOneWidget);
  });

  testWidgets("à venir : une cloche alerte le match sans ouvrir la page (J10)", (tester) async {
    final calls = <String>[];
    await _pump(tester, _event(status: "scheduled", startsAt: "2026-10-18T11:55:00.000Z"), calls: calls);
    await tester.pump();
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pump();
    expect(calls, ["follow event evt-1"]);
    // Alerte active : cloche pleine ; un second tap coupe l'alerte.
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.notifications_active_rounded));
    await tester.pump();
    expect(calls, ["follow event evt-1", "unfollow event evt-1"]);
  });

  testWidgets("en direct, terminé ou reporté : pas de cloche", (tester) async {
    for (final status in ["live", "finished", "postponed"]) {
      await _pump(tester, _event(status: status, scoreA: 1, scoreB: 0));
      await tester.pump();
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing, reason: status);
    }
  });

  testWidgets("la cloche annonce l'échec si l'abonnement échoue", (tester) async {
    await _pump(tester, _event(status: "scheduled", startsAt: "2026-10-18T11:55:00.000Z"), failWith: Exception("réseau"));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pump();
    expect(find.text("Impossible de modifier l'alerte."), findsOneWidget);
  });

  testWidgets("moins de 24 h avant le match : compte à rebours à la place du VS (J10)", (tester) async {
    final start = DateTime.now().toUtc().add(const Duration(hours: 3, minutes: 10, seconds: 30));
    await _pump(tester, _event(status: "scheduled", startsAt: start.toIso8601String()));
    await tester.pump();
    expect(find.text("VS"), findsNothing);
    expect(find.textContaining("03:10:", findRichText: true), findsOneWidget);
    // Démonte le compte à rebours (son `Timer`) avant la fin du test.
    await tester.pumpWidget(const SizedBox());
  });
}
