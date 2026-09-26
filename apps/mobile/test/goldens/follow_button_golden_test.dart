import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/theme/tokens.dart";
import "package:mobile/widgets/follow_button.dart";
import "../golden_helpers.dart";

// Comparé à docs/maquettes/01-valorant-saison.png : pilule "✓ Suivi" du
// header (301,60 → 374,88) pour `following: true`.
void main() {
  setUpAll(loadAppFonts);

  testWidgets("FollowButton : suivi", (tester) async {
    await pumpGolden(
      tester,
      Scaffold(
        backgroundColor: AppColors.background,
        body: const Align(
          alignment: Alignment.topLeft,
          child: Padding(padding: EdgeInsets.all(8), child: FollowButton(following: true)),
        ),
      ),
    );

    await expectLater(find.byType(Scaffold), matchesGoldenFile("golden_files/follow_button_suivi.png"));
  });

  testWidgets("FollowButton : à suivre", (tester) async {
    // Fond approximatif de la carte à dégradé "grand rendez-vous" où ce
    // bouton apparaît dans la maquette (17-accueil.md) : le fond blanc 90 %
    // du bouton est translucide, comparer sur fond neutre fausserait le blanc.
    await pumpGolden(
      tester,
      Scaffold(
        backgroundColor: AppGradients.highlights[0][0],
        body: const Align(
          alignment: Alignment.topLeft,
          child: Padding(padding: EdgeInsets.all(8), child: FollowButton(following: false)),
        ),
      ),
    );

    await expectLater(find.byType(Scaffold), matchesGoldenFile("golden_files/follow_button_suivre.png"));
  });
}
