import "package:flutter_riverpod/flutter_riverpod.dart";
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

/// Comme `_FixedFollowsNotifier` mais `follow`/`unfollow` ne touchent pas au réseau :
/// ils enregistrent l'appel et mettent l'état à jour (J10, cloche des cartes).
class RecordingFollowsNotifier extends FollowsNotifier {
  RecordingFollowsNotifier(this._initial, this.calls, {this.failWith});
  final List<FollowStateDto> _initial;
  final List<String> calls;
  final Object? failWith;

  @override
  Future<List<FollowStateDto>> build() async => _initial;

  @override
  Future<void> follow(FollowTargetType type, String targetId, {String name = "", bool muted = false}) async {
    calls.add("${muted ? "mute" : "follow"} ${type.wire} $targetId");
    if (failWith != null) throw failWith!;
    state = AsyncValue.data([
      ...?state.value?.where((f) => !(f.targetType == type.wire && f.targetId == targetId)),
      FollowStateDto((b) => b
        ..id = "sub-$targetId"
        ..targetType = type.wire
        ..targetId = targetId
        ..muted = muted
        ..level = "all"
        ..notifyReminder = true
        ..notifyStart = true
        ..notifyResult = true
        ..name = name),
    ]);
  }

  @override
  Future<void> unfollow(FollowTargetType type, String targetId) async {
    calls.add("unfollow ${type.wire} $targetId");
    state = AsyncValue.data([...?state.value?.where((f) => !(f.targetType == type.wire && f.targetId == targetId))]);
  }
}

// ignore: strict_top_level_inference
overrideFollowsRecording(List<FollowStateDto> initial, List<String> calls, {Object? failWith}) =>
    followsProvider.overrideWith(() => RecordingFollowsNotifier(initial, calls, failWith: failWith));
