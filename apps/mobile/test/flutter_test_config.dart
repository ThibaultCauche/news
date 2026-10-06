import "dart:async";
import "package:mobile/widgets/match_visuals.dart";

/// Pas de nouvel essai automatique des logos en test : un minuteur en attente fait échouer un test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  imageRetryEnabled = false;
  await testMain();
}
