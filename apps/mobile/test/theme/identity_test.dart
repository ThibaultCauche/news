import "dart:math";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/theme/app_theme.dart";
import "package:mobile/theme/tokens.dart";
import "package:mobile/widgets/page_title.dart";

double _ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  test("le laiton est lisible sur le fond charbon (AA, 4,5:1)", () {
    expect(_ratio(AppColors.brass, AppColors.background), greaterThanOrEqualTo(4.5));
  });

  testWidgets("PageTitle est en Cinzel et garde les accents français", (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const PageTitle("Équipes ÀÉÈÊÇ")));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style?.fontFamily, "Cinzel");
    expect(find.text("Équipes ÀÉÈÊÇ"), findsOneWidget);
  });
}
