import "package:built_value/json_object.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/discussion/shared_cards.dart";
import "package:mobile/features/next_match/next_match_screen.dart";
import "package:mobile/widgets/compact_match_row.dart";
import "package:news_api_client/news_api_client.dart";
import "follows_test_helpers.dart";

EventDetailResponseDto _finished() => EventDetailResponseDto(
  (b) => b
    ..id = "evt-1"
    ..kind = "match"
    ..name = "G2 vs PRX"
    ..status = "finished"
    ..bestOf = 3
    ..importance = 1
    ..sourceUpdatedAt = "2026-10-07T00:00:00.000Z"
    ..result = JsonObject(<String, dynamic>{})
    ..competition.replace(CompetitionRefDto((c) => c..id = "c1"..name = "Playoffs"))
    ..participants.addAll([
      EventParticipantDto((p) => p..entityId = "g2"..name = "G2 Esports"..shortName = "G2"..score = 2..isWinner = true),
      EventParticipantDto((p) => p..entityId = "prx"..name = "Paper Rex"..shortName = "PRX"..score = 1..isWinner = false),
    ]),
);

Future<void> _pump(WidgetTester tester, {required bool spoilerFree}) => tester.pumpWidget(
  ProviderScope(
    key: UniqueKey(),
    overrides: [
      overrideSignedInForTest(),
      overrideFollowsRecording(const [], <String>[]),
      eventProvider("evt-1").overrideWith((ref) async => _finished()),
      userSettingProvider.overrideWith((ref) async => UserSettingDto(
          (b) => b
            ..spoilerFree = spoilerFree
            ..morningDigest = false
            ..notifyForumReplies = true
            ..notifyForumThreads = true
            ..notifyMatchReminder = true
            ..notifyMatchStart = true
            ..notifyMatchResult = true
            ..notifyQualification = true
            ..notifyPredictionReminders = true,
        )),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SharedCard(
          shared: ForumSharedDto((s) => s..kind = ForumSharedDtoKindEnum.event..refId = "evt-1"..locked = false),
          pseudo: "Bob",
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting("fr_FR");
  });

  testWidgets("match partagé, lecteur en sans spoil : le score est flouté", (tester) async {
    await _pump(tester, spoilerFree: true);
    await tester.pumpAndSettle();
    expect(find.text("G2"), findsOneWidget);
    expect(find.byType(ImageFiltered), findsWidgets);
  });

  testWidgets("match partagé, lecteur sans sans spoil : le score est net", (tester) async {
    await _pump(tester, spoilerFree: false);
    await tester.pumpAndSettle();
    expect(tester.widget<CompactMatchRow>(find.byType(CompactMatchRow)).scoresHidden, isFalse);
    expect(find.text("2"), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
  });
}
