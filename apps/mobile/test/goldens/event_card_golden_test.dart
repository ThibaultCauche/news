import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/theme/tokens.dart";
import "package:mobile/widgets/event_card.dart";
import "package:news_api_client/news_api_client.dart";
import "../golden_helpers.dart";
import "../settings_test_helpers.dart";

// Comparé à docs/maquettes/09-agenda.png : ligne "G2-Paper Rex" en direct,
// équipe suivie en or (93,431 → 374,463, cf. docs/maquettes/specs/09-agenda.md).
EventSummaryDto _event() {
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
        ..name = "Valorant · demi-finale · carte 2"))
      ..participants.addAll([
        EventParticipantDto((p) => p
          ..entityId = "team-a"
          ..name = "Fnatic"
          ..score = 1),
        EventParticipantDto((p) => p
          ..entityId = "team-b"
          ..name = "Heretics"
          ..score = 0),
      ]),
  );
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await initializeDateFormatting("fr_FR");
  });

  testWidgets("EventCard : en direct, équipe suivie en or", (tester) async {
    await pumpGolden(
      tester,
      ProviderScope(
        overrides: [overrideCompactEventCardsWith(false)],
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: EventCard(event: _event(), scoresHidden: false, followedEntityIds: const {"team-a"}),
          ),
        ),
      ),
    );

    await expectLater(find.byType(Scaffold), matchesGoldenFile("golden_files/event_card_live_gold.png"));
  });
}
