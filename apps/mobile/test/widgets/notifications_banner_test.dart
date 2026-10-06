import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/widgets/notifications_banner.dart";
import "package:mobile/core/auth/account.dart";
import "../follows_test_helpers.dart";

class _Guest extends SignedInNotifier {
  @override
  bool build() => false;
}

Future<void> _pump(WidgetTester tester, {required bool enabled, bool signedIn = true}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      if (signedIn) overrideSignedInForTest() else signedInProvider.overrideWith(_Guest.new),
      notificationsEnabledProvider.overrideWith((ref) async => enabled),
    ],
    child: const MaterialApp(home: Scaffold(body: NotificationsDisabledBanner())),
  ),
);

void main() {
  testWidgets("notifications coupées : le bandeau le dit et propose d'autoriser (J22)", (tester) async {
    await _pump(tester, enabled: false);
    await tester.pump();
    expect(find.text("Notifications désactivées"), findsOneWidget);
    expect(find.text("Autoriser"), findsOneWidget);
  });

  testWidgets("notifications actives : rien d'affiché", (tester) async {
    await _pump(tester, enabled: true);
    await tester.pump();
    expect(find.text("Notifications désactivées"), findsNothing);
  });

  testWidgets("invité : rien d'affiché (il ne peut pas suivre)", (tester) async {
    await _pump(tester, enabled: false, signedIn: false);
    await tester.pump();
    expect(find.text("Notifications désactivées"), findsNothing);
  });

  testWidgets("« Autoriser » redemande la permission, puis explique où la réactiver", (tester) async {
    await _pump(tester, enabled: false);
    await tester.pump();
    await tester.tap(find.text("Autoriser"));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("Réglages Android"), findsOneWidget);
    expect(find.text("Autoriser"), findsNothing);
  });
}
