import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/widgets/async_view.dart";

Widget _app(AsyncValue<String> value, {VoidCallback? onRetry}) {
  return MaterialApp(
    home: Scaffold(
      body: AsyncView<String>(
        value: value,
        errorMessage: "Impossible de charger le test.",
        onRetry: onRetry ?? () {},
        builder: (data) => Text("contenu $data"),
      ),
    ),
  );
}

void main() {
  testWidgets("le skeleton a un libellé pour les lecteurs d'écran et le contenu apparaît en fondu", (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(const AsyncLoading()));
    expect(find.bySemanticsLabel("Chargement en cours"), findsOneWidget);
    await tester.pumpWidget(_app(const AsyncData("fini")));
    await tester.pump(const Duration(milliseconds: 100));
    // Pendant le fondu : le contenu est déjà là (opacité), le skeleton disparaît à la fin.
    expect(find.text("contenu fini"), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(Skeleton), findsNothing);
    semantics.dispose();
  });

  testWidgets("mouvement réduit : pas de fondu", (tester) async {
    await tester.pumpWidget(MediaQuery(data: const MediaQueryData(disableAnimations: true), child: _app(const AsyncLoading())));
    await tester.pumpWidget(MediaQuery(data: const MediaQueryData(disableAnimations: true), child: _app(const AsyncData("fini"))));
    await tester.pump();
    expect(find.byType(Skeleton), findsNothing);
  });

  testWidgets("premier chargement : un skeleton, jamais un spinner", (tester) async {
    await tester.pumpWidget(_app(const AsyncLoading()));
    expect(find.byType(Skeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  // Un vrai provider : l'invalider donne un `AsyncLoading`/`AsyncError` qui garde la valeur précédente,
  // comme le fait `AutoRefresh` chaque minute.
  Future<(ProviderContainer, Completer<String>)> pumpReloading(WidgetTester tester) async {
    final second = Completer<String>();
    var calls = 0;
    final provider = FutureProvider<String>((ref) => ++calls == 1 ? Future.value("ancien") : second.future);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) => AsyncView<String>(value: ref.watch(provider), onRetry: () {}, builder: (data) => Text("contenu $data"))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // fin du fondu skeleton -> contenu
    final container = ProviderScope.containerOf(tester.element(find.byType(AsyncView<String>)));
    container.invalidate(provider);
    await tester.pump();
    return (container, second);
  }

  testWidgets("rechargement avec une valeur : on garde le contenu, pas de skeleton", (tester) async {
    await pumpReloading(tester);
    expect(find.text("contenu ancien"), findsOneWidget);
    expect(find.byType(Skeleton), findsNothing);
  });

  testWidgets("échec d'un rechargement avec une valeur : le contenu reste", (tester) async {
    final (_, second) = await pumpReloading(tester);
    second.completeError("boom");
    await tester.pump();
    expect(find.text("contenu ancien"), findsOneWidget);
    expect(find.byType(ErrorState), findsNothing);
  });

  testWidgets("erreur sans valeur : message français, rien de technique, « Réessayer » relance", (tester) async {
    var retries = 0;
    await tester.pumpWidget(_app(AsyncError<String>("DioException [bad response]: 500", StackTrace.empty), onRetry: () => retries++));
    expect(find.textContaining("Impossible de charger le test."), findsOneWidget);
    expect(find.textContaining("Dio"), findsNothing);
    expect(find.textContaining("500"), findsNothing);
    await tester.tap(find.text("Réessayer"));
    expect(retries, 1);
  });
}
