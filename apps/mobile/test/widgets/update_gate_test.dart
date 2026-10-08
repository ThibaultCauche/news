import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/app_update.dart";
import "package:mobile/widgets/update_gate.dart";

Future<void> _pump(WidgetTester tester, UpdateLevel level) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appUpdateProvider.overrideWith((ref) async => AppUpdate(level))],
      child: const MaterialApp(home: Scaffold(body: Stack(fit: StackFit.expand, children: [Text("contenu"), UpdateGate()]))),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets("à jour : rien", (tester) async {
    await _pump(tester, UpdateLevel.none);
    expect(find.text("Mettre à jour"), findsNothing);
  });

  testWidgets("sous latest : un bandeau qu'on peut fermer", (tester) async {
    await _pump(tester, UpdateLevel.suggested);
    expect(find.text("Une mise à jour de Keryx est disponible."), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.text("Mettre à jour"), findsNothing);
  });

  testWidgets("sous minSupported : un écran bloquant, sans bouton fermer", (tester) async {
    await _pump(tester, UpdateLevel.required);
    expect(find.text("Mise à jour nécessaire"), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });
}
