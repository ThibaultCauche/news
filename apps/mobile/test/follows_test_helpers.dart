import "package:mobile/features/follows/follows_provider.dart";
import "package:news_api_client/news_api_client.dart";

class _FixedFollowsNotifier extends FollowsNotifier {
  _FixedFollowsNotifier(this._value);
  final List<FollowStateDto> _value;

  @override
  Future<List<FollowStateDto>> build() async => _value;
}

/// `followsProvider` est un `AsyncNotifier` depuis le J8 (retour optimiste du
/// bouton Suivre) : ce repli fige son contenu dans les tests, à la place de
/// l'ancien `followsProvider.overrideWith((ref) async => value)`.
// ignore: strict_top_level_inference (le type `Override` n'est pas exporté par flutter_riverpod)
overrideFollowsWith(List<FollowStateDto> value) => followsProvider.overrideWith(() => _FixedFollowsNotifier(value));
