import "package:built_collection/built_collection.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/onboarding/onboarding_flow.dart";
import "package:mobile/features/team/team_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

EntityOrganizationDto _org({int teamCount = 2}) => EntityOrganizationDto((b) => b
  ..id = "org-g2"
  ..name = "G2 Esports"
  ..teamCount = teamCount
  ..games = ListBuilder<String>(["league-of-legends", "valorant"]));

Widget _app(List<String> calls, {List<FollowStateDto> follows = const []}) => ProviderScope(
      overrides: [overrideFollowsRecording(follows, calls), overrideSignedInForTest()],
      child: MaterialApp(home: Scaffold(body: OrganizationFollowTile(organization: _org()))),
    );

FollowStateDto _followed() => FollowStateDto((b) => b
  ..id = "sub-org"
  ..targetType = "organization"
  ..targetId = "org-g2"
  ..level = "all"
  ..notifyReminder = false
  ..notifyStart = true
  ..notifyResult = true
  ..muted = false
  ..name = "G2 Esports");

void main() {
  testWidgets("« Suivre toute G2 » : la structure et ses jeux, un appui suit la structure", (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_app(calls));
    await tester.pumpAndSettle();

    expect(find.text("Toute G2 Esports"), findsOneWidget);
    expect(find.text("2 équipes · League of Legends, Valorant"), findsOneWidget);

    await tester.tap(find.text("Suivre"));
    await tester.pumpAndSettle();
    expect(calls, ["follow organization org-g2"]);
  });

  testWidgets("une structure déjà suivie se retire d'un appui", (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_app(calls, follows: [_followed()]));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Suivi"));
    await tester.pumpAndSettle();
    expect(calls, ["unfollow organization org-g2"]);
  });

  test("onboarding : Valorant est coché au départ, on ajoute LoL, mais on ne décoche pas le dernier jeu", () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(onboardingGamesProvider, (_, _) {});
    final games = container.read(onboardingGamesProvider.notifier);

    expect(container.read(onboardingGamesProvider), {"valorant"});
    games.toggle("league-of-legends");
    expect(container.read(onboardingGamesProvider), {"valorant", "league-of-legends"});
    games.toggle("valorant");
    expect(container.read(onboardingGamesProvider), {"league-of-legends"});
    games.toggle("league-of-legends");
    expect(container.read(onboardingGamesProvider), {"league-of-legends"});
  });
}
