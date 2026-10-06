import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/widgets/match_visuals.dart";
import "package:mobile/core/navigation.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/bracket/bracket_screen.dart";
import "package:mobile/features/follows/follows_screen.dart";
import "package:mobile/features/team/team_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";
import "../settings_test_helpers.dart";

FollowStateDto _follow({
  required String targetType,
  required String targetId,
  required String name,
  EventSummaryDto? currentEvent,
  String? imageUrl,
  FollowStateDtoStatusEnum? status,
}) {
  return FollowStateDto((b) {
    b
      ..id = "sub-$targetId"
      ..targetType = targetType
      ..targetId = targetId
      ..level = "all"
      ..notifyReminder = true
      ..notifyStart = true
      ..notifyResult = true
      ..muted = false
      ..name = name
      ..imageUrl = imageUrl
      ..status = status;
    if (currentEvent != null) b.currentEvent.replace(currentEvent);
  });
}

EventSummaryDto _liveEvent() {
  return EventSummaryDto(
    (b) => b
      ..id = "evt-1"
      ..kind = "match"
      ..name = "G2 Esports vs Paper Rex"
      ..status = "live"
      ..bestOf = 3
      ..importance = 3
      ..competition.replace(CompetitionRefDto((c) => c
        ..id = "comp-1"
        ..name = "Champions 2026"))
      ..participants.addAll(<EventParticipantDto>[]),
  );
}

Future<void> _pump(WidgetTester tester, List<FollowStateDto> follows) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        overrideFollowsWith(follows),
        userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
          ..spoilerFree = false
          ..morningDigest = false)),
        overrideCompactEventCardsWith(false),
        logoIsDarkProvider("https://example.test/g2.png").overrideWith((ref) async => false),
        // Pages ouvertes par un tap sur le nom : pas de réseau en test.
        entityProvider("team-a").overrideWith((ref) async => throw Exception("hors ligne")),
        competitionDetailProvider("comp-1").overrideWith((ref) async => throw Exception("hors ligne")),
      ],
      child: MaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: FollowsScreen())),
    ),
  );
}

void main() {
  testWidgets("aucun suivi : message d'accueil, pas de carte", (tester) async {
    await _pump(tester, const []);
    await tester.pumpAndSettle();
    expect(find.textContaining("Tu ne suis rien"), findsOneWidget);
  });

  testWidgets("un suivi avec match en direct : nom et match affichés", (tester) async {
    // `pump()`, pas `pumpAndSettle()` : le point "en direct" pulse en continu
    // (`LiveDot`), une animation qui ne se termine jamais.
    await _pump(tester, [_follow(targetType: "entity", targetId: "team-a", name: "Test G2", currentEvent: _liveEvent())]);
    await tester.pump();
    await tester.pump();
    expect(find.text("Test G2"), findsOneWidget);
    expect(find.textContaining("G2 Esports"), findsOneWidget);
  });

  testWidgets("un suivi sans match prévu : message plutôt qu'une carte vide", (tester) async {
    await _pump(tester, [_follow(targetType: "competition", targetId: "comp-1", name: "VCT 2026")]);
    await tester.pumpAndSettle();
    expect(find.text("VCT 2026"), findsOneWidget);
    expect(find.text("Rien de prévu pour l'instant."), findsOneWidget);
  });

  testWidgets("équipe encore en course : logo et statut affichés", (tester) async {
    await _pump(tester, [
      _follow(targetType: "entity", targetId: "team-a", name: "Test G2", imageUrl: "https://example.test/g2.png", status: FollowStateDtoStatusEnum.qualified),
    ]);
    await tester.pumpAndSettle();
    // `NetworkImage` tente un vrai appel réseau ici, qui échoue toujours en
    // test (pas de réseau) : attendu, seule l'URL demandée nous intéresse.
    tester.takeException();

    expect(find.text("ENCORE EN COURSE"), findsOneWidget);
    final logo = tester.widget<Image>(find.byType(Image));
    expect((logo.image as CachedNetworkImageProvider).url, "https://example.test/g2.png");
  });

  testWidgets("équipe éliminée : statut affiché, pas de logo sans imageUrl", (tester) async {
    await _pump(tester, [_follow(targetType: "entity", targetId: "team-a", name: "Test G2", status: FollowStateDtoStatusEnum.eliminated)]);
    await tester.pumpAndSettle();

    expect(find.text("ÉLIMINÉE"), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets("suivi d'une compétition : pas de logo ni de statut d'équipe", (tester) async {
    await _pump(tester, [_follow(targetType: "competition", targetId: "comp-1", name: "VCT 2026")]);
    await tester.pumpAndSettle();

    expect(find.byType(TeamBadge), findsNothing);
  });

  testWidgets("plus de « x » : le désabonnement se fait depuis la page (J10)", (tester) async {
    await _pump(tester, [_follow(targetType: "competition", targetId: "comp-1", name: "VCT 2026")]);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets("le nom d'une équipe suivie mène à sa fiche", (tester) async {
    await _pump(tester, [_follow(targetType: "entity", targetId: "team-a", name: "Test G2")]);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Test G2"));
    await tester.pumpAndSettle();
    expect(find.byType(TeamScreen), findsOneWidget);
  });

  testWidgets("le nom d'une compétition suivie mène à sa page", (tester) async {
    await _pump(tester, [_follow(targetType: "competition", targetId: "comp-1", name: "VCT 2026")]);
    await tester.pumpAndSettle();
    await tester.tap(find.text("VCT 2026"));
    await tester.pumpAndSettle();
    expect(find.byType(BracketScreen), findsOneWidget);
  });

  testWidgets("aucun suivi : le bouton mène à l'onglet Compétitions", (tester) async {
    await _pump(tester, const []);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Explorer les compétitions"));
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(FollowsScreen)));
    expect(container.read(tabIndexProvider), competitionsTabIndex);
  });
}
