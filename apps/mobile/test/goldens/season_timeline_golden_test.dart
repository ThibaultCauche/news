import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/theme/tokens.dart";
import "package:mobile/widgets/season_timeline.dart";
import "../golden_helpers.dart";

// Comparé à docs/maquettes/01-valorant-saison.png : frise de la carte
// "Saison 2026" (33,306 → 357,352, cf. docs/maquettes/specs/01-valorant-saison.md).
void main() {
  setUpAll(loadAppFonts);

  testWidgets("SeasonTimeline : Stage 2 en cours", (tester) async {
    await pumpGolden(
      tester,
      Scaffold(
        backgroundColor: AppColors.surface,
        body: const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: SeasonTimeline(
            steps: [
              SeasonStep(label: "Kickoff", kind: SeasonStepKind.done),
              SeasonStep(label: "Masters", kind: SeasonStepKind.done, milestone: true),
              SeasonStep(label: "Stage 1", kind: SeasonStepKind.done),
              SeasonStep(label: "Masters", kind: SeasonStepKind.done, milestone: true),
              SeasonStep(label: "Stage 2", kind: SeasonStepKind.current),
              SeasonStep(label: "Pause", kind: SeasonStepKind.upcoming),
            ],
          ),
        ),
      ),
    );

    await expectLater(find.byType(Scaffold), matchesGoldenFile("golden_files/season_timeline_stage2.png"));
  });
}
