import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/theme/tokens.dart";
import "package:mobile/widgets/glass_tab_bar.dart";
import "../golden_helpers.dart";

// Démonstration du socle golden (étape 2 de la passe de fidélité visuelle) :
// police Inter réelle, canevas 390×844, comparé ensuite à
// docs/maquettes/17-accueil.png (bande 762-844) par
// test/goldens/compare_golden.py. Les briques de l'étape 3 auront chacune
// leur propre golden ; celui-ci ne fait que prouver que le mécanisme marche.
const _items = [
  GlassTabBarItem(icon: Icons.wb_sunny_rounded, label: "Aujourd'hui"),
  GlassTabBarItem(icon: Icons.calendar_today_rounded, label: "Agenda"),
  GlassTabBarItem(icon: Icons.star_rounded, label: "Suivis"),
  GlassTabBarItem(icon: Icons.casino_rounded, label: "Jeu"),
];

void main() {
  setUpAll(loadAppFonts);

  testWidgets("tab bar en verre : Aujourd'hui actif", (tester) async {
    await pumpGolden(
      tester,
      Scaffold(
        backgroundColor: AppColors.background,
        extendBody: true,
        body: const SizedBox.expand(),
        bottomNavigationBar: const GlassTabBar(items: _items, currentIndex: 0, onTap: _noop),
      ),
    );

    await expectLater(find.byType(Scaffold), matchesGoldenFile("golden_files/glass_tab_bar_aujourdhui.png"));
  });
}

void _noop(int _) {}
