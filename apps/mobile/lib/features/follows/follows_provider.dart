import "dart:async";

import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/notifications/push_service.dart";

/// Catégorie/compétition/entité/événement (docs/03 §2) : type applicatif,
/// converti vers l'énum propre à chaque DTO généré (`CreateSubscriptionDto`,
/// `SubscriptionTargetDto`) au moment de l'appel.
enum FollowTargetType { category, competition, entity, event }

final followsProvider = FutureProvider.autoDispose<List<FollowStateDto>>((ref) async {
  final response = await ref.watch(apiClientProvider).getSubscriptionsApi().subscriptionsControllerList();
  return response.data!.toList();
});

bool isFollowing(List<FollowStateDto>? follows, FollowTargetType type, String targetId) {
  return follows?.any((f) => f.targetType == type.name && f.targetId == targetId) ?? false;
}

/// Un seul point d'entrée pour suivre/ne plus suivre depuis n'importe quel
/// écran (bouton "Suivre" partout, docs/04 J4) : invalide `followsProvider`
/// pour que toutes les pastilles se mettent à jour, et enregistre l'appareil
/// pour les notifications au premier suivi.
class FollowsController {
  FollowsController(this._ref);

  final Ref _ref;

  Future<void> follow(FollowTargetType type, String targetId) async {
    await _ref.read(apiClientProvider).getSubscriptionsApi().subscriptionsControllerCreate(
      createSubscriptionDto: CreateSubscriptionDto((b) => b..targetType = _toCreateEnum(type)..targetId = targetId),
    );
    _ref.invalidate(followsProvider);
    unawaited(_ref.read(pushServiceProvider).ensureRegistered());
  }

  Future<void> unfollow(FollowTargetType type, String targetId) async {
    await _ref.read(apiClientProvider).getSubscriptionsApi().subscriptionsControllerRemove(
      subscriptionTargetDto: SubscriptionTargetDto((b) => b..targetType = _toTargetEnum(type)..targetId = targetId),
    );
    _ref.invalidate(followsProvider);
  }
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
