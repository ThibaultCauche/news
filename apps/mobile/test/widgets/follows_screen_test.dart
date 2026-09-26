import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/follows/follows_provider.dart";
import "package:mobile/features/follows/follows_screen.dart";
import "package:news_api_client/news_api_client.dart";

FollowStateDto _follow({required String targetType, required String targetId, required String name, EventSummaryDto? currentEvent}) {
  return FollowStateDto((b) {
    b
      ..id = "sub-$targetId"
      ..targetType = targetType
      ..targetId = targetId
      ..level = "all"
      ..notifyReminder = true
      ..notifyStart = true
      ..notifyResult = true
      ..name = name;
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
        followsProvider.overrideWith((ref) async => follows),
        userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
          ..spoilerFree = false
          ..morningDigest = false)),
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
}
