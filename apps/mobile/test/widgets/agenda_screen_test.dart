import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/agenda/agenda_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../settings_test_helpers.dart";

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _mondayOf(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // N'importe quelle fenêtre demandée : seule la navigation entre
        // semaines est testée ici, pas le contenu de la liste (J8).
        agendaProvider.overrideWith((ref, query) async => AgendaResponseDto((b) => b..sourceUpdatedAt = "2026-09-27T00:00:00Z")),
        userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
          ..spoilerFree = false
          ..morningDigest = false)),
        overrideCompactEventCardsWith(false),
        await overrideAuthStoreForTest(),
      ],
      child: const MaterialApp(home: Scaffold(body: AgendaScreen())),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting("fr_FR");
  });

  testWidgets("flèche suivante avance la semaine affichée de 7 jours", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    final today = _dateOnly(DateTime.now());
    final nextMonday = _mondayOf(today).add(const Duration(days: 7));

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();

    expect(find.text("${nextMonday.day}"), findsOneWidget);
  });

  testWidgets("flèche précédente permet de revenir avant aujourd'hui", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    final today = _dateOnly(DateTime.now());
    final previousMonday = _mondayOf(today).subtract(const Duration(days: 7));

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();

    expect(find.text("${previousMonday.day}"), findsOneWidget);
  });

  testWidgets("la flèche suivante se désactive à la borne +14 jours", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    final nextButton = find.widgetWithIcon(IconButton, Icons.chevron_right_rounded);

    // Au plus 4 semaines suffisent à couvrir toute fenêtre ±14 jours.
    for (var i = 0; i < 4; i++) {
      if (tester.widget<IconButton>(nextButton).onPressed == null) break;
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
    }

    expect(tester.widget<IconButton>(nextButton).onPressed, isNull);
  });
}
