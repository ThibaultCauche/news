import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/theme/tokens.dart";
import "package:mobile/widgets/segmented_control.dart";
import "../golden_helpers.dart";

// Comparé à docs/maquettes/01-valorant-saison.png : piste (16,189 → 374,223).
void main() {
  setUpAll(loadAppFonts);

  testWidgets("SegmentedControl : Saison actif", (tester) async {
    await pumpGolden(
      tester,
      Scaffold(
        backgroundColor: AppColors.background,
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SegmentedControl(
            labels: const ["Saison", "Tournoi", "Équipes", "Agenda"],
            selectedIndex: 0,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await expectLater(find.byType(Scaffold), matchesGoldenFile("golden_files/segmented_control_saison.png"));
  });
}
