import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/theme/tokens.dart";
import "package:mobile/widgets/page_subtitle.dart";
import "package:mobile/widgets/page_title.dart";
import "../golden_helpers.dart";

// Comparé à docs/maquettes/09-agenda.png, bande du titre (y≈124-180),
// pattern standard "titre puis sous-titre" utilisé par 01/02/03/06/09.
void main() {
  setUpAll(loadAppFonts);

  testWidgets("PageTitle + PageSubtitle : Agenda", (tester) async {
    await pumpGolden(
      tester,
      Scaffold(
        backgroundColor: AppColors.background,
        body: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [PageTitle("Agenda"), PageSubtitle("Tout ce que tu suis, au même endroit")],
          ),
        ),
      ),
    );

    await expectLater(find.byType(Scaffold), matchesGoldenFile("golden_files/page_header_agenda.png"));
  });
}
