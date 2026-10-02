import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/auth/account.dart";
import "../account/account_gate.dart";

/// Profil (pseudo, e-mail vérifié, stats de pronostics) ; `null` pour un invité.
final profileProvider = FutureProvider.autoDispose<ProfileDto?>((ref) async {
  if (!ref.watch(signedInProvider)) return null;
  return (await ref.watch(apiClientProvider).getCommunityApi().communityControllerGetProfile()).data!;
});

/// Profil d'un autre joueur (membre d'un groupe commun).
final publicProfileProvider = FutureProvider.autoDispose.family<PublicProfileDto, String>((ref, userId) async {
  return (await ref.watch(apiClientProvider).getCommunityApi().communityControllerGetPublicProfile(id: userId)).data!;
});

final groupsProvider = FutureProvider.autoDispose<List<GroupDto>>((ref) async {
  if (!ref.watch(signedInProvider)) return const [];
  return (await ref.watch(apiClientProvider).getCommunityApi().communityControllerListGroups()).data!.toList();
});

/// Classement d'un groupe ; `game` (slug) limite les points aux matchs de ce jeu, `null` = tous (J14).
final groupDetailProvider = FutureProvider.autoDispose.family<GroupDetailDto, ({String id, String? game})>((ref, key) async {
  return (await ref.watch(apiClientProvider).getCommunityApi().communityControllerGetGroup(id: key.id, game: key.game)).data!;
});

/// Choix des amis sur un match : vide tant que le match n'a pas commencé (masqué par le serveur, J14).
final friendsPicksProvider = FutureProvider.autoDispose.family<List<FriendPickDto>, String>((ref, eventId) async {
  if (!ref.watch(signedInProvider)) return const [];
  return (await ref.watch(apiClientProvider).getCommunityApi().communityControllerFriendsPicks(id: eventId)).data!.picks.toList();
});

/// Mes pronostics, par match. Vide pour un invité.
final predictionsProvider = FutureProvider.autoDispose<Map<String, PredictionDto>>((ref) async {
  if (!ref.watch(signedInProvider)) return const {};
  final list = (await ref.watch(apiClientProvider).getCommunityApi().communityControllerListPredictions()).data!;
  return {for (final p in list) p.eventId: p};
});

/// Choix affiché tout de suite pendant l'envoi d'un pronostic (J15), par match ; retiré à la fin de
/// l'appel (réussi ou non : en cas d'échec, l'affichage revient au pronostic enregistré).
typedef PendingPick = ({String entityId, int? picked, int? other});

class PendingPicksNotifier extends Notifier<Map<String, PendingPick>> {
  @override
  Map<String, PendingPick> build() => const {};

  void set(String eventId, PendingPick? pick) {
    final next = {...state};
    if (pick == null) {
      next.remove(eventId);
    } else {
      next[eventId] = pick;
    }
    state = next;
  }
}

final pendingPicksProvider = NotifierProvider<PendingPicksNotifier, Map<String, PendingPick>>(PendingPicksNotifier.new);

/// Logo d'avatar choisi mais pas encore confirmé par le serveur (J19) : affiché à la place de l'avatar du profil.
class PendingAvatarNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? url) => state = url;
}

final pendingAvatarProvider = NotifierProvider<PendingAvatarNotifier, String?>(PendingAvatarNotifier.new);

/// Actions communautaires : chacune exige un compte, et un pseudo pour les pronostics et groupes.
class CommunityController {
  CommunityController(this._ref);

  final Ref _ref;

  CommunityApi get _api => _ref.read(apiClientProvider).getCommunityApi();

  /// L'avatar est le logo d'une équipe (`entity`). Le logo choisi s'affiche tout de suite
  /// (`pendingAvatarProvider`) et n'est retiré qu'une fois le vrai profil rechargé ; en cas d'échec,
  /// l'ancien avatar revient et l'erreur remonte.
  Future<void> setAvatar(String teamEntityId, String avatarUrl) async {
    final pending = _ref.read(pendingAvatarProvider.notifier);
    pending.set(avatarUrl);
    try {
      await _api.communityControllerSetProfile(putProfileDto: PutProfileDto((b) => b..avatarEntityId = teamEntityId));
      _ref.invalidate(profileProvider);
      _ref.invalidate(groupsProvider);
      await _ref.read(profileProvider.future);
    } finally {
      pending.set(null);
    }
  }

  Future<void> setPseudo(String pseudo) async {
    await _api.communityControllerSetProfile(putProfileDto: PutProfileDto((b) => b..pseudo = pseudo));
    _ref.invalidate(profileProvider);
  }

  /// `false` si l'utilisateur a refusé de créer un compte.
  Future<bool> predict(String eventId, String pickedEntityId, {int? pickedScore, int? otherScore}) async {
    if (!await ensureAccount(_ref)) return false;
    await _api.communityControllerPutPrediction(
      putPredictionDto: PutPredictionDto((b) {
        b
          ..eventId = eventId
          ..pickedEntityId = pickedEntityId;
        if (pickedScore != null && otherScore != null) {
          b
            ..pickedScore = pickedScore
            ..otherScore = otherScore;
        }
      }),
    );
    // On attend le rechargement : le choix affiché tout de suite (`pendingPicksProvider`) n'est retiré
    // qu'une fois la vraie valeur en place.
    _ref.invalidate(predictionsProvider);
    await _ref.read(predictionsProvider.future);
    return true;
  }

  Future<GroupDto> createGroup(String name) async {
    final group = (await _api.communityControllerCreateGroup(createGroupDto: CreateGroupDto((b) => b..name = name))).data!;
    _ref.invalidate(groupsProvider);
    return group;
  }

  Future<GroupDto> joinGroup(String code) async {
    final group = (await _api.communityControllerJoinGroup(joinGroupDto: JoinGroupDto((b) => b..code = code.trim().toUpperCase()))).data!;
    _ref.invalidate(groupsProvider);
    return group;
  }

  Future<void> leaveGroup(String id) async {
    await _api.communityControllerLeaveGroup(id: id);
    _ref.invalidate(groupsProvider);
  }

  Future<void> deleteGroup(String id) async {
    await _api.communityControllerDeleteGroup(id: id);
    _ref.invalidate(groupsProvider);
  }
}

final communityControllerProvider = Provider((ref) => CommunityController(ref));
