import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/theme/tokens.dart";
import "package:mobile/widgets/section_card.dart";
import "package:mobile/widgets/section_label.dart";
import "../golden_helpers.dart";

// Comparé à docs/maquettes/05-repechage.png, carte "Comment ça marche"
// (16,245 → 374,351 : 358×106, cf. docs/maquettes/specs/05-repechage.md).
void main() {
  setUpAll(loadAppFonts);

  testWidgets("SectionCard : Comment ça marche", (tester) async {
    await pumpGolden(
      tester,
      Scaffold(
        backgroundColor: AppColors.background,
        body: const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: SectionCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel("COMMENT ÇA MARCHE"),
                SizedBox(height: AppSpacing.sm),
                Text(
                  "Battu dans le tableau principal ? On rejoue ici. "
                  "Une défaite de plus et c’est fini. Le vainqueur "
                  "retrouve le finaliste du haut en grande finale.",
                  style: TextStyle(
                    fontFamily: "Inter",
                    fontSize: AppTypography.body,
                    height: AppTypography.lineHeight,
                    color: Color(0xB3F5F5F7), // blanc 70 %, cf. docs/maquettes/specs/05-repechage.md
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await expectLater(find.byType(Scaffold), matchesGoldenFile("golden_files/section_card_repechage.png"));
  });
}
