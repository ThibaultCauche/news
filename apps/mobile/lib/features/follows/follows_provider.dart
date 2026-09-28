import "dart:async";

import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/notifications/push_service.dart";

/// Catégorie/compétition/entité/événement (docs/03 §2) : type applicatif,
/// converti vers l'énum propre à chaque DTO généré (`CreateSubscriptionDto`,
/// `SubscriptionTargetDto`) au moment de l'appel.
enum FollowTargetType { category, competition, entity, event }

/// `AsyncNotifier` plutôt que `FutureProvider` (comme avant le J8) : il faut
/// pouvoir modifier `state` à la main pour le retour optimiste de
/// `follow`/`unfollow` (le bouton "Suivre" ne changeait de texte qu'après
/// l'aller-retour réseau, latence perçue signalée au J8) — un `FutureProvider`
/// ne l'autorise pas depuis l'extérieur.
class FollowsNotifier extends AsyncNotifier<List<FollowStateDto>> {
  @override
  Future<List<FollowStateDto>> build() async {
    final response = await ref.watch(apiClientProvider).getSubscriptionsApi().subscriptionsControllerList();
    return response.data!.toList();
  }

  Future<void> follow(FollowTargetType type, String targetId, {String name = ""}) async {
    final previous = state;
    final current = previous.value;
    if (current != null) {
      state = AsyncValue.data([
        ...current,
        FollowStateDto(
          (b) => b
            ..id = "optimistic-$targetId"
            ..targetType = type.name
            ..targetId = targetId
            ..level = "all"
            ..notifyReminder = true
            ..notifyStart = true
            ..notifyResult = true
            ..name = name,
        ),
      ]);
    }
    try {
      await ref.read(apiClientProvider).getSubscriptionsApi().subscriptionsControllerCreate(
        createSubscriptionDto: CreateSubscriptionDto((b) => b..targetType = _toCreateEnum(type)..targetId = targetId),
      );
    } catch (_) {
      state = previous;
      rethrow;
    }
    ref.invalidateSelf();
    unawaited(ref.read(pushServiceProvider).ensureRegistered());
  }

  Future<void> unfollow(FollowTargetType type, String targetId) async {
    final previous = state;
    final current = previous.value;
    if (current != null) {
      state = AsyncValue.data(current.where((f) => !(f.targetType == type.name && f.targetId == targetId)).toList());
    }
    try {
      await ref.read(apiClientProvider).getSubscriptionsApi().subscriptionsControllerRemove(
        subscriptionTargetDto: SubscriptionTargetDto((b) => b..targetType = _toTargetEnum(type)..targetId = targetId),
      );
    } catch (_) {
      state = previous;
      rethrow;
    }
    ref.invalidateSelf();
  }
}

final followsProvider = AsyncNotifierProvider.autoDispose<FollowsNotifier, List<FollowStateDto>>(FollowsNotifier.new);

bool isFollowing(List<FollowStateDto>? follows, FollowTargetType type, String targetId) {
  return follows?.any((f) => f.targetType == type.name && f.targetId == targetId) ?? false;
}

/// Un seul point d'entrée pour suivre/ne plus suivre depuis n'importe quel
/// écran (bouton "Suivre" partout, docs/04 J4) : délègue à `FollowsNotifier`,
/// qui porte la mise à jour optimiste et l'appel réseau.
class FollowsController {
  FollowsController(this._ref);

  final Ref _ref;

  Future<void> follow(FollowTargetType type, String targetId, {String name = ""}) =>
      _ref.read(followsProvider.notifier).follow(type, targetId, name: name);

  Future<void> unfollow(FollowTargetType type, String targetId) => _ref.read(followsProvider.notifier).unfollow(type, targetId);
}

final followsControllerProvider = Provider((ref) => FollowsController(ref));

CreateSubscriptionDtoTargetTypeEnum _toCreateEnum(FollowTargetType t) => switch (t) {
  FollowTargetType.category => CreateSubscriptionDtoTargetTypeEnum.category,
  FollowTargetType.competition => CreateSubscriptionDtoTargetTypeEnum.competition,
  FollowTargetType.entity => CreateSubscriptionDtoTargetTypeEnum.entity,
  FollowTargetType.event => CreateSubscriptionDtoTargetTypeEnum.event,
};

SubscriptionTargetDtoTargetTypeEnum _toTargetEnum(FollowTargetType t) => switch (t) {
  FollowTargetType.category => SubscriptionTargetDtoTargetTypeEnum.category,
  FollowTargetType.competition => SubscriptionTargetDtoTargetTypeEnum.competition,
  FollowTargetType.entity => SubscriptionTargetDtoTargetTypeEnum.entity,
  FollowTargetType.event => SubscriptionTargetDtoTargetTypeEnum.event,
};
