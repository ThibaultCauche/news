import "package:built_collection/built_collection.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/forum/forum_providers.dart";
import "package:mobile/features/team/team_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

// Fiche d'un joueur (J27) : sa poule, ses résultats par tournoi, ses adversaires fréquents.
EntityResponseDto _player() => EntityResponseDto((b) => b
  ..id = "p-sonix"
  ..kind = "player"
  ..name = "Sonix"
  ..wins = 7
  ..losses = 0
  ..winStreak = 7
  ..sourceUpdatedAt = "2026-10-07T00:00:00Z"
  ..tournaments = ListBuilder<EntityTournamentDto>([
    EntityTournamentDto((t) => t
      ..competitionId = "serie-genesis"
      ..name = "Genesis X3"
      ..wins = 7
      ..losses = 0),
  ])
  ..rivals = ListBuilder<EntityRivalDto>([
    EntityRivalDto((r) => r
      ..entityId = "p-zomba"
      ..name = "Zomba"
      ..wins = 2
      ..losses = 1),
  ]));

EventSummaryDto _poolSet() => EventSummaryDto((b) => b
  ..id = "e-pool"
  ..kind = "match"
  ..name = "Winners Round 1: Sonix vs Hurt"
  ..status = "scheduled"
  ..importance = 3
  ..competition.update((c) => c
    ..id = "pools"
    ..name = "Round 1 Pools")
  ..participants = ListBuilder<EventParticipantDto>([
    EventParticipantDto((p) => p
      ..entityId = "p-sonix"
      ..name = "Sonix"),
    EventParticipantDto((p) => p
      ..entityId = "p-hurt"
      ..name = "Hurt"),
  ]));

Widget _app({bool withPool = true}) => ProviderScope(
      overrides: [
        overrideFollowsWith(const []),
        entityProvider("p-sonix").overrideWith((ref) async => _player()),
        entityPoolProvider("p-sonix").overrideWith(
          (ref) async => EntityPoolDto((b) => b
            ..group = "E409"
            ..phaseName = "Round 1 Pools"
            ..tournamentName = "Genesis X3"
            ..events = ListBuilder<EventSummaryDto>(withPool ? [_poolSet()] : [])),
        ),
        forumThreadProvider.overrideWith((ref, key) async => null),
      ],
      child: const MaterialApp(home: TeamScreen(entityId: "p-sonix", breadcrumb: "Smash")),
    );

void main() {
  testWidgets("joueur : sa poule, ses tournois et ses adversaires fréquents", (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text("SA POULE · E409"), findsOneWidget);
    expect(find.text("TOURNOIS"), findsOneWidget);
    expect(find.text("Genesis X3"), findsOneWidget);
    expect(find.text("ADVERSAIRES FRÉQUENTS"), findsOneWidget);
    expect(find.text("Zomba"), findsOneWidget);
    // Sans spoil par défaut : les bilans par tournoi et par adversaire sont cachés (le 3ᵉ « — » est « Prochain match »).
    expect(find.text("—"), findsNWidgets(3));
    expect(find.text("2–1"), findsNothing);
  });

  testWidgets("joueur sans poule connue : pas de section « Sa poule »", (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(withPool: false));
    await tester.pumpAndSettle();

    expect(find.textContaining("SA POULE"), findsNothing);
    expect(find.text("TOURNOIS"), findsOneWidget);
  });
}
