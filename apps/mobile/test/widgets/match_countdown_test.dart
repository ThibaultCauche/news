import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/widgets/match_countdown.dart";

void main() {
  test("formatCountdown : toujours HH:MM:SS, jours devant au-delà de 24 h", () {
    expect(formatCountdown(const Duration(days: 2, hours: 4, minutes: 30, seconds: 12)), "2j 04:30:12");
    expect(formatCountdown(const Duration(hours: 3, minutes: 5, seconds: 40)), "03:05:40");
    expect(formatCountdown(const Duration(minutes: 42, seconds: 59)), "00:42:59");
    expect(formatCountdown(const Duration(seconds: 1)), "00:00:01");
    expect(formatCountdown(Duration.zero), "Imminent");
    expect(formatCountdown(const Duration(seconds: -5)), "Imminent");
  });

  // Horloge simulée : avance de la durée passée à `pump` (pas de `DateTime.now` réel en test).
  var elapsed = Duration.zero;
  final origin = DateTime(2026, 10, 18, 12);

  Future<void> pumpCountdown(WidgetTester tester, {bool reducedMotion = false}) {
    elapsed = Duration.zero;
    return tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MatchCountdown(startsAt: origin.add(const Duration(hours: 2, seconds: 30)), now: () => origin.add(elapsed)),
        ),
      ),
    );
  }

  // Couleur de chaque ":" du texte : transparente pendant la moitié "éteinte" du clignotement.
  List<Color?> colonColors(WidgetTester tester) {
    // `Text.rich` enveloppe notre `TextSpan` dans le sien : on parcourt l'arbre entier.
    final root = tester.widget<RichText>(find.byType(RichText).first).text;
    final colors = <Color?>[];
    root.visitChildren((span) {
      if (span is TextSpan && span.text == ":") colors.add(span.style?.color);
      return true;
    });
    expect(colors, isNotEmpty);
    return colors;
  }

  testWidgets("les deux-points clignotent à chaque seconde", (tester) async {
    await pumpCountdown(tester);
    final seen = <bool>{};
    for (var i = 0; i < 4; i++) {
      seen.add(colonColors(tester).every((c) => c == Colors.transparent));
      elapsed += const Duration(seconds: 1);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(seen, {true, false});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("mouvement réduit : les deux-points restent fixes", (tester) async {
    await pumpCountdown(tester, reducedMotion: true);
    for (var i = 0; i < 4; i++) {
      expect(colonColors(tester).every((c) => c != Colors.transparent), isTrue);
      elapsed += const Duration(seconds: 1);
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpWidget(const SizedBox());
  });
}
