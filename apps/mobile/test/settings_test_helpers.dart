import "package:mobile/core/api_providers.dart";
import "package:mobile/core/auth/auth_store.dart";
import "package:mobile/core/settings_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

class _FixedCompactEventCardsNotifier extends CompactEventCardsNotifier {
  _FixedCompactEventCardsNotifier(this._value);
  final bool _value;

  @override
  bool build() => _value;
}

/// `compactEventCardsProvider` lit `authStoreProvider` (`shared_preferences`),
/// jamais construit avec sa valeur par défaut en dehors des tests : ce repli
/// fige son contenu sans avoir à fournir un `AuthStore` de test, même principe
/// que `overrideFollowsWith` (`follows_test_helpers.dart`).
// ignore: strict_top_level_inference (le type `Override` n'est pas exporté par flutter_riverpod)
overrideCompactEventCardsWith(bool value) => compactEventCardsProvider.overrideWith(() => _FixedCompactEventCardsNotifier(value));

/// `AuthStore` en mémoire (`shared_preferences` avec des valeurs de départ
/// vides) : `authStoreProvider` n'est "jamais construit avec sa valeur par
/// défaut en dehors des tests" (`api_providers.dart`), donc tout écran qui le
/// lit directement (ex. `AgendaScreen.initState`, filtre mémorisé J8) en a
/// besoin, pas seulement ceux qui passent par `compactEventCardsProvider`.
// ignore: strict_top_level_inference (le type `Override` n'est pas exporté par flutter_riverpod)
overrideAuthStoreForTest() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return authStoreProvider.overrideWithValue(AuthStore(prefs));
}
