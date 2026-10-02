import "dart:async";

import "package:built_value/json_object.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/profile/community_providers.dart";
import "package:mobile/features/profile/prediction_panel.dart";
import "package:news_api_client/news_api_client.dart";

EventDetailResponseDto _event() => EventDetailResponseDto((b) => b
  ..id = "evt-1"
  ..kind = "match"
  ..name = "G2 vs TL"
  ..status = "scheduled"
  ..bestOf = 3
  ..importance = 3
  ..sourceUpdatedAt = "2026-10-02T00:00:00.000Z"
  ..result = JsonObject(<String, dynamic>{})
  ..competition.replace(CompetitionRefDto((c) => c
    ..id = "comp-1"
    ..name = "Champions 2026"))
  ..participants.addAll([
    EventParticipantDto((p) => p
      ..entityId = "team-a"
      ..name = "G2 Esports"
      ..shortName = "G2"),
    EventParticipantDto((p) => p
      ..entityId = "team-b"
      ..name = "Team Liquid"
      ..shortName = "TL"),
  ])
  ..context.replace(EventContextDto()));

/// Un serveur lent : chaque envoi attend qu'on le libère (`release`).
class _SlowController implements CommunityController {
  final sent = <String>[];
  final _gates = <Completer<void>>[];

  void release() => _gates.removeAt(0).complete();

  @override
  Future<bool> predict(String eventId, String pickedEntityId, {int? pickedScore, int? otherScore}) async {
    sent.add(pickedEntityId);
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets("pronostic : un nouvel appui pendant un envoi lent s'affiche aussitôt et part ensuite, sans être perdu", (tester) async {
    final slow = _SlowController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          communityControllerProvider.overrideWithValue(slow),
          predictionsProvider.overrideWith((ref) async => <String, PredictionDto>{}),
        ],
        child: MaterialApp(home: Scaffold(body: PredictionPanel(event: _event(), scoresHidden: false))),
      ),
    );
    await tester.pump();

    await tester.tap(find.text("G2"));
    await tester.pump();
    expect(slow.sent, ["team-a"]);

    // Le serveur n'a pas encore répondu : TL s'affiche choisi tout de suite, mais rien d'autre n'est parti.
    await tester.tap(find.text("TL"));
    await tester.pump();
    expect(slow.sent, ["team-a"], reason: "un seul envoi à la fois");
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, "TL")).onPressed, isNull, reason: "TL est le choix affiché");

    slow.release();
    await tester.pump();
    await tester.pump();
    expect(slow.sent, ["team-a", "team-b"], reason: "le dernier choix part dès que le premier est fini");

    slow.release();
    await tester.pumpAndSettle();
  });
}
