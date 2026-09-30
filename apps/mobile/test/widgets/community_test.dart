import "package:built_value/json_object.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/auth/account.dart";
import "package:mobile/features/follows/follows_provider.dart";
import "package:mobile/features/profile/community_providers.dart";
import "package:mobile/features/profile/prediction_panel.dart";
import "package:mobile/features/profile/profile_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

class _GuestNotifier extends SignedInNotifier {
  @override
  bool build() => false;
}

class _RecordingCommunity extends CommunityController {
  _RecordingCommunity(super.ref, this.calls);
  final List<String> calls;

  @override
  Future<bool> predict(String eventId, String pickedEntityId, {int? pickedScore, int? otherScore}) async {
    calls.add("$eventId $pickedEntityId ${pickedScore ?? "-"}-${otherScore ?? "-"}");
    return true;
  }
}

EventDetailResponseDto _event(String status) => EventDetailResponseDto(
      (b) => b
        ..id = "evt-1"
        ..kind = "match"
        ..name = "G2 vs PRX"
        ..status = status
        ..startsAt = "2026-10-18T17:00:00.000Z"
        ..bestOf = 3
        ..importance = 1
        ..sourceUpdatedAt = "2026-10-18T10:00:00.000Z"
        ..competition.replace(CompetitionRefDto((c) => c
          ..id = "c"
          ..name = "Champions"))
        ..participants.addAll([
          EventParticipantDto((p) => p
            ..entityId = "g2"
            ..name = "G2 Esports"
            ..shortName = "G2"),
          EventParticipantDto((p) => p
            ..entityId = "prx"
            ..name = "Paper Rex"
            ..shortName = "PRX"),
        ])
        ..result = JsonObject(<String, Object?>{})
        ..context.replace(EventContextDto((c) => c)),
    );

void main() {
  testWidgets("l'invité voit l'invitation à créer un compte sur l'onglet Profil", (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [signedInProvider.overrideWith(_GuestNotifier.new)],
      child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
    ));
    expect(find.text("Tu navigues en invité"), findsOneWidget);
    expect(find.text("Créer un compte"), findsOneWidget);
    expect(find.text("Mes suivis"), findsNothing);
  });

  test("un invité ne peut pas suivre : l'action n'atteint pas le serveur", () async {
    final calls = <String>[];
    final container = ProviderContainer(overrides: [signedInProvider.overrideWith(_GuestNotifier.new), overrideFollowsRecording(const [], calls)]);
    addTearDown(container.dispose);
    container.listen(followsProvider, (_, _) {});
    // Pas de `navigatorKey` monté : la fenêtre « Crée un compte » ne peut pas s'ouvrir, donc refus.
    await container.read(followsControllerProvider).follow(FollowTargetType.entity, "g2");
    expect(calls, isEmpty);
  });

  testWidgets("pronostic : choisir un vainqueur puis un score enregistre chaque choix", (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        overrideSignedInForTest(),
        predictionsProvider.overrideWith((ref) async => {
              "evt-1": PredictionDto((p) => p
                ..eventId = "evt-1"
                ..pickedEntityId = "g2"),
            }),
        communityControllerProvider.overrideWith((ref) => _RecordingCommunity(ref, calls)),
      ],
      child: MaterialApp(home: Scaffold(body: PredictionPanel(event: _event("scheduled"), scoresHidden: false))),
    ));
    await tester.pump();
    await tester.tap(find.text("PRX"));
    await tester.pump();
    await tester.tap(find.text("2-1"));
    await tester.pump();
    expect(calls, ["evt-1 prx ---", "evt-1 g2 2-1"]);
  });

  testWidgets("pronostic : verrouillé une fois le match commencé, points masqués sans spoil", (tester) async {
    Future<void> show(String status, {required bool hidden}) => tester.pumpWidget(ProviderScope(
          overrides: [
            overrideSignedInForTest(),
            predictionsProvider.overrideWith((ref) async => {
                  "evt-1": PredictionDto((p) => p
                    ..eventId = "evt-1"
                    ..pickedEntityId = "g2"
                    ..points = 5),
                }),
          ],
          child: MaterialApp(home: Scaffold(body: PredictionPanel(event: _event(status), scoresHidden: hidden))),
        ));
    await show("finished", hidden: true);
    await tester.pump();
    expect(find.text("Points gagnés : •••"), findsOneWidget);
    expect(find.textContaining("Verrouillé"), findsOneWidget);
    await show("finished", hidden: false);
    await tester.pump();
    expect(find.text("Points gagnés : 5"), findsOneWidget);
  });
}
