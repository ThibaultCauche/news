import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/theme/app_theme.dart";

/// Charge Inter depuis l'asset local pour que les tests golden rendent le
/// vrai texte (pas la police de secours "Ahem" utilisée par défaut dans les
/// tests Flutter). À appeler une fois par fichier de test (`setUpAll`).
Future<void> loadAppFonts() async {
  final fontData = await rootBundle.load("assets/fonts/Inter.ttf");
  final loader = FontLoader("Inter")..addFont(Future.value(fontData));
  await loader.load();
}

/// Prépare le testeur pour un golden à l'échelle des maquettes : 390×844,
/// devicePixelRatio 1 (mêmes dimensions que les PNG de `docs/maquettes/`),
/// textScale 1,0 (docs/maquettes/specs/commun.md — pas d'estimation ici, le
/// gabarit doit matcher exactement le canevas Figma).
Future<void> pumpGolden(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MediaQuery(
      // `disableAnimations` : un golden doit être une image stable, et des
      // bricks comme `LiveDot` pulsent en continu (`repeat(reverse: true)`)
      // — sans ça `pumpAndSettle` ne se stabiliserait jamais.
      data: const MediaQueryData(size: Size(390, 844), textScaler: TextScaler.linear(1), disableAnimations: true),
      child: MaterialApp(theme: buildAppTheme(), debugShowCheckedModeBanner: false, home: child),
    ),
  );
  await tester.pump();
}
