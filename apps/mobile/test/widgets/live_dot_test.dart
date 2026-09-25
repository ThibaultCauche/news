import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/widgets/live_dot.dart";

Future<void> _pump(WidgetTester tester, {required bool disableAnimations}) {
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: const MaterialApp(home: Scaffold(body: LiveDot())),
    ),
  );
}

void main() {
  // `find.byType(FadeTransition)` seul remonterait aussi les transitions de
  // route de `MaterialApp` : on ne regarde que le sous-arbre du `LiveDot`.
  Finder fadeWithinDot() => find.descendant(of: find.byType(LiveDot), matching: find.byType(FadeTransition));

  testWidgets("mouvement normal : le point pulse en continu (FadeTransition)", (tester) async {
    await _pump(tester, disableAnimations: false);
    expect(fadeWithinDot(), findsOneWidget);
  });

  testWidgets("mouvement réduit : le point reste fixe, pas d'animation", (tester) async {
    await _pump(tester, disableAnimations: true);
    expect(fadeWithinDot(), findsNothing);
    expect(
      find.descendant(of: find.byType(LiveDot), matching: find.byType(DecoratedBox)),
      findsOneWidget,
    );
  });
}
