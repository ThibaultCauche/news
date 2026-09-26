import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/widgets/live_badge.dart";
import "../golden_helpers.dart";

// Comparé à docs/maquettes/17-accueil.png : badge "EN DIRECT" de la carte
// "Maintenant" (35,158 → 122,176, cf. docs/maquettes/specs/17-accueil.md).
void main() {
  setUpAll(loadAppFonts);

  testWidgets("LiveBadge : EN DIRECT", (tester) async {
    await pumpGolden(
      tester,
      const Scaffold(
        backgroundColor: Color(0xFF3B1219), // dégradé de la carte "Maintenant", cf. AppGradients.highlights[0]... variante rouge
        body: Align(alignment: Alignment.topLeft, child: Padding(padding: EdgeInsets.all(8), child: LiveBadge("EN DIRECT"))),
      ),
    );

    await expectLater(find.byType(Scaffold), matchesGoldenFile("golden_files/live_badge_en_direct.png"));
  });
}
