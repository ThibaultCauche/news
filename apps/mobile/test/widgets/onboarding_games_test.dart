import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/onboarding/onboarding_flow.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

void main() {
  teamsPageTest();
  testWidgets("onboarding : sur un petit écran rien ne déborde, et on choisit un deuxième jeu", (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: OnboardingFlow(onDone: () {}))));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("1 jeu choisi"), findsOneWidget);
    expect(find.text("Je ne connais pas Valorant"), findsOneWidget);
    expect(find.text("Je ne connais pas League of Legends"), findsNothing);

    await tester.ensureVisible(find.text("League of Legends"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("League of Legends"));
    await tester.pumpAndSettle();
    expect(find.text("2 jeux choisis"), findsOneWidget);
    expect(find.text("Je ne connais pas League of Legends"), findsOneWidget);

    // « Continuer » reste atteignable sans défiler la page, et le choix survit au changement de page
    // (les suggestions d'équipes de la dernière page en dépendent).
    await tester.tap(find.text("Continuer"));
    await tester.pumpAndSettle();
    expect(find.text("Tu regardes en quelle langue ?"), findsOneWidget);
    expect(ProviderScope.containerOf(tester.element(find.byType(OnboardingFlow))).read(onboardingGamesProvider), {"valorant", "league-of-legends"});
  });
}

EntityResponseDto _team(String name, String game, String region) => EntityResponseDto((b) => b
  ..id = "$game-$name"
  ..kind = "team"
  ..name = name
  ..shortName = "G2"
  ..game = game
  ..region = region
  ..wins = 0
  ..losses = 0
  ..winStreak = 0
  ..sourceUpdatedAt = "2026-10-01T00:00:00Z");

void teamsPageTest() {
  testWidgets("suggestions d'équipes : le jeu est sous le nom, même avec une région longue, sans débordement", (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        suggestedTeamsProvider.overrideWith((ref) async => [
              (_team("G2 Esports", "league-of-legends", "demo-worlds"), "Le grand nom de l'Europe."),
              (_team("G2 Esports", "valorant", "DE"), "Favori de Champions."),
            ]),
        overrideFollowsWith(const []),
      ],
      child: MaterialApp(home: OnboardingFlow(onDone: () {})),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Continuer"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Continuer"));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // La liste est paresseuse : seule la première carte tient à l'écran.
    expect(find.text("G2 Esports"), findsOneWidget);
    expect(find.text("League of Legends · demo-worlds"), findsOneWidget);
  });
}
