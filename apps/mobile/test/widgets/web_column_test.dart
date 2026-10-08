import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/widgets/web_column.dart";

void main() {
  testWidgets("WebColumn limite la largeur et la rapporte à MediaQuery", (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    double? seen;
    await tester.pumpWidget(
      MaterialApp(
        home: WebColumn(child: Builder(builder: (c) => Text("${seen = MediaQuery.of(c).size.width}"))),
      ),
    );
    expect(seen, webColumnMaxWidth);
    expect(tester.getSize(find.byType(SizedBox).first).width, webColumnMaxWidth);
  });
}
