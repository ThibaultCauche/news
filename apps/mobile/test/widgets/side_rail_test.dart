import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/theme/app_theme.dart";
import "package:mobile/widgets/glass_tab_bar.dart";
import "package:mobile/widgets/responsive.dart";
import "package:mobile/widgets/side_rail.dart";

void main() {
  testWidgets("SideRail : un appui change d'onglet", (tester) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SideRail(
            items: const [GlassTabBarItem(icon: Icons.home, label: "Accueil"), GlassTabBarItem(icon: Icons.chat, label: "Discussion", badge: 2)],
            currentIndex: 0,
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    );
    await tester.tap(find.text("Discussion"));
    expect(tapped, 1);
    expect(find.text("2"), findsOneWidget);
  });

  testWidgets("un écran poussé reste dans une colonne en mode ordinateur, pas sur téléphone", (tester) async {
    addTearDown(tester.view.reset);
    Future<double> pushedWidth(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: SizedBox.expand(key: Key("page"))))),
              child: const Text("ouvrir"),
            ),
          ),
        ),
      );
      await tester.tap(find.text("ouvrir"));
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(const Key("page"))).width;
    }

    expect(await pushedWidth(const Size(1400, 900)), kPageMaxWidth);
    expect(await pushedWidth(const Size(390, 800)), 390);
  });
}
