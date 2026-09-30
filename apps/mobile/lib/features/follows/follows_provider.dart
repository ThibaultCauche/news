import "dart:async";

import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/auth/account.dart";
import "../../core/notifications/push_service.dart";
import "../account/account_gate.dart";

/// Catégorie/compétition/entité/événement (docs/03 §2) : type applicatif,
/// converti vers l'énum propre à chaque DTO généré (`CreateSubscriptionDto`,
/// `SubscriptionTargetDto`) au moment de l'appel.
enum FollowTargetType { category, competition, competitionFamily, entity, event }

/// Valeur échangée avec l'API (`competition_family`), différente du nom Dart de l'énum.
extension FollowTargetTypeWire on FollowTargetType {
  String get wire => this == FollowTargetType.competitionFamily ? "competition_family" : name;
}

FollowTargetType followTargetTypeFromWire(String wire) => FollowTargetType.values.firstWhere((t) => t.wire == wire);

/// `AsyncNotifier` plutôt que `FutureProvider` (comme avant le J8) : il faut
/// pouvoir modifier `state` à la main pour le retour optimiste de
/// `follow`/`unfollow` (le bouton "Suivre" ne changeait de texte qu'après
/// l'aller-retour réseau, latence perçue signalée au J8) — un `FutureProvider`
/// ne l'autorise pas depuis l'extérieur.
class FollowsNotifier extends AsyncNotifier<List<FollowStateDto>> {
  @override
  Future<List<FollowStateDto>> build() async {
    // Invité : aucun suivi (il faut un compte pour suivre, docs/04 J11).
    if (!ref.watch(signedInProvider)) return [];
    final response = await ref.watch(apiClientProvider).getSubscriptionsApi().subscriptionsControllerList();
    return response.data!.toList();
  }

  Future<void> follow(FollowTargetType type, String targetId, {String name = "", bool muted = false}) async {
    final previous = state;
    final current = previous.value;
    if (current != null) {
      state = AsyncValue.data([
        ...current.where((f) => !(f.targetType == type.wire && f.targetId == targetId)),
        FollowStateDto(
          (b) => b
            ..id = "optimistic-$targetId"
            ..targetType = type.wire
            ..targetId = targetId
            ..muted = muted
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
        createSubscriptionDto: CreateSubscriptionDto((b) => b..targetType = _toCreateEnum(type)..targetId = targetId..muted = muted),
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
      state = AsyncValue.data(current.where((f) => !(f.targetType == type.wire && f.targetId == targetId)).toList());
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

/// Suivi actif : une ligne en sourdine (`muted`) n'est pas un suivi.
bool isFollowing(List<FollowStateDto>? follows, FollowTargetType type, String targetId) {
  return follows?.any((f) => f.targetType == type.wire && f.targetId == targetId && !f.muted) ?? false;
}

/// Compétition mise en sourdine : « je suis la ligue, sauf celle-ci » (J10).
bool isMuted(List<FollowStateDto>? follows, FollowTargetType type, String targetId) {
  return follows?.any((f) => f.targetType == type.wire && f.targetId == targetId && f.muted) ?? false;
}

/// Un seul point d'entrée pour suivre/ne plus suivre depuis n'importe quel
/// écran (bouton "Suivre" partout, docs/04 J4) : délègue à `FollowsNotifier`,
/// qui porte la mise à jour optimiste et l'appel réseau.
class FollowsController {
  FollowsController(this._ref);

  final Ref _ref;

  // Le compte est exigé ici, au point de passage commun de tous les boutons « Suivre » : après
  // une connexion réussie dans la foulée, le suivi demandé est appliqué.
  Future<void> follow(FollowTargetType type, String targetId, {String name = "", bool muted = false}) async {
    // Connecté : on ne cède pas la main avant l'appel, pour que la mise à jour optimiste du
    // bouton soit immédiate (J8) ; seul l'invité passe par la fenêtre de connexion.
    if (!_ref.read(signedInProvider) && !await ensureAccount(_ref)) return;
    await _ref.read(followsProvider.notifier).follow(type, targetId, name: name, muted: muted);
  }

  Future<void> unfollow(FollowTargetType type, String targetId) async {
    if (!_ref.read(signedInProvider) && !await ensureAccount(_ref)) return;
    await _ref.read(followsProvider.notifier).unfollow(type, targetId);
  }
}

final followsControllerProvider = Provider((ref) => FollowsController(ref));

CreateSubscriptionDtoTargetTypeEnum _toCreateEnum(FollowTargetType t) => switch (t) {
  FollowTargetType.category => CreateSubscriptionDtoTargetTypeEnum.category,
  FollowTargetType.competition => CreateSubscriptionDtoTargetTypeEnum.competition,
  FollowTargetType.competitionFamily => CreateSubscriptionDtoTargetTypeEnum.competitionFamily,
  FollowTargetType.entity => CreateSubscriptionDtoTargetTypeEnum.entity,
  FollowTargetType.event => CreateSubscriptionDtoTargetTypeEnum.event,
};

SubscriptionTargetDtoTargetTypeEnum _toTargetEnum(FollowTargetType t) => switch (t) {
  FollowTargetType.category => SubscriptionTargetDtoTargetTypeEnum.category,
  FollowTargetType.competition => SubscriptionTargetDtoTargetTypeEnum.competition,
  FollowTargetType.competitionFamily => SubscriptionTargetDtoTargetTypeEnum.competitionFamily,
  FollowTargetType.entity => SubscriptionTargetDtoTargetTypeEnum.entity,
  FollowTargetType.event => SubscriptionTargetDtoTargetTypeEnum.event,
};
