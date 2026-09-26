import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/bracket/kickoff_lives_screen.dart";
import "package:news_api_client/news_api_client.dart";

CompetitionStandingDto _standing({required String entityId, required String name, required int livesLeft, bool qualified = false}) {
  return CompetitionStandingDto((b) => b
    ..entityId = entityId
    ..entityName = name
    ..rank = 4 - livesLeft
    ..livesLeft = livesLeft
    ..qualified = qualified);
}

Future<void> _pump(WidgetTester tester) {
  final competition = CompetitionResponseDto((b) => b
    ..id = "kickoff"
    ..name = "Kickoff EMEA"
    ..kind = "tournament"
    ..sourceUpdatedAt = "2026-01-20T00:00:00Z"
    ..standings.addAll([
      _standing(entityId: "fnc", name: "Fnatic", livesLeft: 3, qualified: true),
      _standing(entityId: "kc", name: "Karmine Corp", livesLeft: 2),
      _standing(entityId: "th", name: "Team Heretics", livesLeft: 0),
    ]));

  return tester.pumpWidget(
    ProviderScope(
      overrides: [competitionDetailProvider("kickoff").overrideWith((ref) async => competition)],
      child: const MaterialApp(
        home: KickoffLivesScreen(competitionId: "kickoff", title: "Kickoff EMEA", subtitle: "Terminé"),
      ),
    ),
  );
}

void main() {
  testWidgets("groupe les équipes par vies restantes, qualifiée mise en avant", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining("TABLEAU PRINCIPAL"), findsOneWidget);
    expect(find.textContaining("2ᵉ CHANCE"), findsOneWidget);
    expect(find.textContaining("ÉLIMINÉES"), findsOneWidget);
    expect(find.text("Fnatic"), findsOneWidget);
    expect(find.text("Qualifié"), findsOneWidget);
  });
}
