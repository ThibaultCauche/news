import "dart:async";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/auth/account.dart";
import "../../core/navigation.dart";
import "../../core/notifications/notification_tap_handler.dart";
import "../account/account_gate.dart";
import "forum_terms.dart";

/// Accès au forum (docs/04 J13) : ouvert ou non (bêta fermée), ce que l'utilisateur peut y faire.
/// En cas d'erreur réseau, le forum est considéré fermé : ses entrées disparaissent des écrans.
final forumStatusProvider = FutureProvider.autoDispose<ForumStatusDto>((ref) async {
  ref.watch(signedInProvider);
  try {
    return (await ref.watch(apiClientProvider).getForumApi().forumControllerStatus()).data!;
  } catch (_) {
    return ForumStatusDto(
      (b) => b
        ..enabled = false
        ..signedIn = false
        ..canPost = false
        ..termsVersion = forumTermsVersion
        ..termsAccepted = false
        ..isModerator = false,
    );
  }
});

/// Vrai quand le forum est ouvert à cet utilisateur.
final forumEnabledProvider = Provider.autoDispose<bool>((ref) => ref.watch(forumStatusProvider).value?.enabled ?? false);

/// Fil d'un match, d'une équipe, d'une compétition ou d'un jeu : créé par le serveur à la première
/// ouverture. `null` si le forum est fermé ou la cible inconnue.
final forumThreadProvider = FutureProvider.autoDispose.family<ForumThreadDto?, ({String kind, String targetId})>((ref, key) async {
  if (!ref.watch(forumEnabledProvider)) return null;
  try {
    return (await ref.watch(apiClientProvider).getForumApi().forumControllerResolveThread(kind: key.kind, targetId: key.targetId)).data!;
  } catch (_) {
    return null;
  }
});

/// Discussions d'un jeu : celles où l'on parle, plus les discussions libres.
final forumThreadsProvider = FutureProvider.autoDispose.family<List<ForumThreadDto>, ({String? game, String sort, String? kind})>((ref, key) async {
  if (!ref.watch(forumEnabledProvider)) return const [];
  return (await ref.watch(apiClientProvider).getForumApi().forumControllerListThreads(game: key.game, kind: key.kind, sort: key.sort)).data!.toList();
});

/// Boîte « Discussion » (J24) : groupes, messages privés, fils suivis ou où j'ai écrit, avec non-lus.
/// Vide pour un invité.
final inboxProvider = FutureProvider.autoDispose<List<InboxItemDto>>((ref) async {
  if (!ref.watch(signedInProvider)) return const [];
  return (await ref.watch(apiClientProvider).getForumApi().forumControllerGetInbox()).data!.toList();
});

/// Messages non lus de toute la boîte (pastille de l'onglet).
final unreadCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(inboxProvider).value?.fold<int>(0, (sum, i) => sum + i.unreadCount.toInt()) ?? 0;
});

/// Joueurs à qui l'on peut écrire en privé : les membres de mes groupes.
final forumContactsProvider = FutureProvider.autoDispose<List<ForumContactDto>>((ref) async {
  if (!ref.watch(signedInProvider)) return const [];
  return (await ref.watch(apiClientProvider).getForumApi().forumControllerContacts()).data!.toList();
});

/// Recherche de discussions publiques (équipes, compétitions, jeux, fils libres).
final forumSearchProvider = FutureProvider.autoDispose.family<List<ForumSearchResultDto>, String>((ref, q) async {
  return (await ref.watch(apiClientProvider).getForumApi().forumControllerSearch(q: q)).data!.toList();
});

final forumCampsProvider = FutureProvider.autoDispose<List<ForumCampDto>>((ref) async {
  if (!ref.watch(signedInProvider)) return const [];
  return (await ref.watch(apiClientProvider).getForumApi().forumControllerListCamps()).data!.toList();
});

final forumBlocksProvider = FutureProvider.autoDispose<List<BlockedUserDto>>((ref) async {
  if (!ref.watch(signedInProvider)) return const [];
  return (await ref.watch(apiClientProvider).getForumApi().forumControllerListBlocks()).data!.toList();
});

final moderationLogProvider = FutureProvider.autoDispose<List<ModerationLogDto>>((ref) async {
  return (await ref.watch(apiClientProvider).getModerationApi().moderationControllerLog()).data!.toList();
});

final moderationReportsProvider = FutureProvider.autoDispose<List<ReportedMessageDto>>((ref) async {
  return (await ref.watch(apiClientProvider).getModerationApi().moderationControllerReports()).data!.toList();
});

/// Messages racines d'un fil (les plus récents d'abord), avec leurs réponses.
class ForumMessagesState {
  const ForumMessagesState({
    required this.thread,
    required this.messages,
    required this.nextBefore,
    this.unreadCount = 0,
    this.firstUnreadId,
    this.seenAt,
    this.typing,
  });

  final ForumThreadDto thread;
  final List<ForumMessageDto> messages;
  final String? nextBefore;
  // Fil privé (J24) : nouveaux messages à l'ouverture, « Vu » et « écrit… » d'un message privé.
  final int unreadCount;
  final String? firstUnreadId;
  final DateTime? seenAt;
  final String? typing;

  ForumMessagesState withMessages(List<ForumMessageDto> next, {String? nextBefore, bool keepNextBefore = false}) => ForumMessagesState(
    thread: thread,
    messages: next,
    nextBefore: keepNextBefore ? this.nextBefore : nextBefore,
    unreadCount: unreadCount,
    firstUnreadId: firstUnreadId,
    seenAt: seenAt,
    typing: typing,
  );

  static ForumMessagesState fromPage(ForumMessagesPageDto page, List<ForumMessageDto> messages, String? nextBefore) => ForumMessagesState(
    thread: page.thread,
    messages: messages,
    nextBefore: nextBefore,
    unreadCount: page.unreadCount?.toInt() ?? 0,
    firstUnreadId: page.firstUnreadId,
    seenAt: page.seenAt,
    typing: page.typing,
  );
}

class ForumMessagesNotifier extends AsyncNotifier<ForumMessagesState> {
  ForumMessagesNotifier(this.threadId);

  final String threadId;

  ForumApi get _api => ref.read(apiClientProvider).getForumApi();

  @override
  Future<ForumMessagesState> build() async {
    ref.watch(signedInProvider); // « ma réaction » dépend du compte
    final page = (await _api.forumControllerListMessages(id: threadId)).data!;
    return ForumMessagesState.fromPage(page, page.messages.toList(), page.nextBefore);
  }

  /// Recharge la première page sans perdre les pages plus anciennes déjà chargées.
  Future<void> refresh() async {
    final current = state.value;
    final page = (await _api.forumControllerListMessages(id: threadId)).data!;
    final fresh = page.messages.toList();
    if (current == null || fresh.isEmpty) {
      state = AsyncData(ForumMessagesState.fromPage(page, fresh, page.nextBefore));
      return;
    }
    final oldest = fresh.last.createdAt;
    final older = current.messages.where((m) => m.createdAt.isBefore(oldest)).toList();
    state = AsyncData(ForumMessagesState.fromPage(page, [...fresh, ...older], older.isEmpty ? page.nextBefore : current.nextBefore));
  }

  /// Réaction affichée tout de suite (J15), avant la réponse du serveur : le compteur et « ma réaction »
  /// sont recalculés localement ; `refresh()` remet la vérité du serveur ensuite (ou après un échec).
  void showReaction(String messageId, String emojiName, {required bool remove}) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.withMessages([for (final m in current.messages) _withReaction(m, messageId, remove ? null : emojiName)], keepNextBefore: true));
  }

  static ForumMessageDto _withReaction(ForumMessageDto m, String id, String? next) {
    final replies = m.replies.map((r) => _withReaction(r, id, next)).toList();
    if (m.id != id) return m.rebuild((b) => b.replies.replace(replies));
    final counts = {for (final r in m.reactions) r.emoji.name: r.count.toInt()};
    final previous = m.myReaction;
    if (previous != null) counts[previous] = (counts[previous] ?? 1) - 1;
    if (next != null) counts[next] = (counts[next] ?? 0) + 1;
    final reactions = ReactionCountDtoEmojiEnum.values
        .where((e) => (counts[e.name] ?? 0) > 0)
        .map((e) => ReactionCountDto((b) => b..emoji = e..count = counts[e.name]!))
        .toList();
    return m.rebuild((b) {
      b.reactions.replace(reactions);
      b.replies.replace(replies);
      b.myReaction = next;
    });
  }

  Future<void> loadMore() async {
    final current = state.value;
    final before = current?.nextBefore;
    if (current == null || before == null) return;
    final page = (await _api.forumControllerListMessages(id: threadId, before: before)).data!;
    state = AsyncData(current.withMessages([...current.messages, ...page.messages], nextBefore: page.nextBefore));
  }
}

final forumMessagesProvider = AsyncNotifierProvider.autoDispose.family<ForumMessagesNotifier, ForumMessagesState, String>(ForumMessagesNotifier.new);

/// Pourquoi on ne peut pas écrire, en français (codes du serveur, `ForumStatusDto.blockedReason`).
String forumBlockedMessage(String? code) => switch (code) {
  "PROFILE_REQUIRED" => "Crée ton profil (pseudo) pour participer.",
  "ACCOUNT_TOO_NEW" => "Ton compte doit avoir 24 h d'ancienneté pour écrire. À demain !",
  "BANNED" => "Tu as été exclu du forum.",
  "TERMS_REQUIRED" => "Accepte les conditions d'utilisation du forum.",
  _ => "Tu ne peux pas écrire pour l'instant.",
};

class ForumController {
  ForumController(this._ref);

  final Ref _ref;

  ForumApi get _api => _ref.read(apiClientProvider).getForumApi();

  /// Vérifie, pas à pas, qu'on peut écrire : compte, pseudo, conditions acceptées, ancienneté,
  /// exclusion. Affiche la raison si ce n'est pas le cas. `true` si on peut continuer.
  Future<bool> ensureCanPost(BuildContext context) async {
    if (!await ensureAccount(_ref)) return false;
    var status = await _refreshStatus();
    if (status.blockedReason == "TERMS_REQUIRED") {
      final navigator = navigatorKey.currentState;
      final accepted = navigator == null ? null : await navigator.push<bool>(MaterialPageRoute(builder: (_) => const ForumTermsScreen(requireAcceptance: true)));
      if (accepted != true) return false;
      status = (await _api.forumControllerAcceptTerms(acceptTermsDto: AcceptTermsDto((b) => b..version = status.termsVersion.toInt()))).data!;
      _ref.invalidate(forumStatusProvider);
    }
    if (!status.canPost) {
      final messenger = navigatorKey.currentContext == null ? null : ScaffoldMessenger.maybeOf(navigatorKey.currentContext!);
      messenger?.showSnackBar(SnackBar(content: Text(forumBlockedMessage(status.blockedReason))));
      return false;
    }
    return true;
  }

  Future<ForumStatusDto> _refreshStatus() async {
    _ref.invalidate(forumStatusProvider);
    return _ref.read(forumStatusProvider.future);
  }

  Future<void> post(String threadId, String body, {String? parentId, bool isSpoiler = false, List<String>? pollOptions, int? pollHours}) async {
    await _api.forumControllerPostMessage(
      id: threadId,
      postMessageDto: PostMessageDto((b) {
        b.body = body;
        if (parentId != null) b.parentId = parentId;
        if (isSpoiler) b.isSpoiler = true;
        if (pollOptions != null) b.pollOptions.replace(pollOptions);
        if (pollHours != null) b.pollHours = PostMessageDtoPollHoursEnum.valueOf("n$pollHours");
      }),
    );
    await _ref.read(forumMessagesProvider(threadId).notifier).refresh();
    _ref.invalidate(forumThreadsProvider);
    _ref.invalidate(forumThreadProvider);
    _ref.invalidate(inboxProvider);
  }

  /// Sourdine d'un fil privé : plus de notification de nouveaux messages.
  Future<void> setMuted(String threadId, bool muted) async {
    if (muted) {
      await _api.forumControllerMute(id: threadId);
    } else {
      await _api.forumControllerUnmute(id: threadId);
    }
    await _ref.read(forumMessagesProvider(threadId).notifier).refresh();
    _ref.invalidate(inboxProvider);
  }

  /// « X écrit… » : signal envoyé pendant la frappe d'un message privé (l'erreur est sans importance).
  void sendTyping(String threadId) {
    unawaited(_api.forumControllerTyping(id: threadId).then<void>((_) {}, onError: (_) {}));
  }

  /// Compte connecté ? Sinon déroule la création de compte (la Discussion est réservée aux comptes).
  Future<bool> ensureSignedIn() => ensureAccount(_ref);

  /// Ouvre (ou crée) le message privé avec un membre de l'un de mes groupes.
  Future<ForumThreadDto> openDm(String userId) async {
    final thread = (await _api.forumControllerOpenDm(createDmDto: CreateDmDto((b) => b..userId = userId))).data!;
    _ref.invalidate(inboxProvider);
    return thread;
  }

  Future<ForumThreadDto> groupThread(String groupId) async {
    final thread = (await _api.forumControllerGroupThread(id: groupId)).data!;
    _ref.invalidate(inboxProvider);
    return thread;
  }

  /// Envoie une carte (match, compétition, pronostic) dans un fil : seul l'identifiant part.
  Future<void> share(String threadId, ShareDtoKindEnum kind, String refId) async {
    await _api.forumControllerPostMessage(
      id: threadId,
      postMessageDto: PostMessageDto((b) {
        b.body = "";
        b.share.kind = kind;
        b.share.refId = refId;
      }),
    );
    _ref.invalidate(inboxProvider);
    _ref.invalidate(forumMessagesProvider(threadId));
  }

  /// Vote d'un sondage ; `option` nul retire le vote.
  Future<void> vote(String threadId, String messageId, int? option) async {
    if (!await ensureAccount(_ref)) return;
    if (option == null) {
      await _api.forumControllerDeleteVote(id: messageId);
    } else {
      await _api.forumControllerPutVote(id: messageId, voteDto: VoteDto((b) => b..option = option));
    }
    await _ref.read(forumMessagesProvider(threadId).notifier).refresh();
  }

  Future<void> setIdeaStatus(String threadId, String messageId, SetIdeaStatusDtoStatusEnum? status) async {
    if (status == null) {
      await _moderation.moderationControllerClearIdeaStatus(id: messageId);
    } else {
      await _moderation.moderationControllerSetIdeaStatus(id: messageId, setIdeaStatusDto: SetIdeaStatusDto((b) => b..status = status));
    }
    await _ref.read(forumMessagesProvider(threadId).notifier).refresh();
  }

  /// Corrige son message (dans les 5 minutes après sa publication).
  Future<void> editMessage(String threadId, String messageId, String body) async {
    await _api.forumControllerEditMessage(id: messageId, editMessageDto: EditMessageDto((b) => b..body = body));
    await _ref.read(forumMessagesProvider(threadId).notifier).refresh();
  }

  /// Suit ou ne suit plus une discussion (notification des nouveaux messages).
  Future<void> setFollow(String threadId, bool follow) async {
    if (!await ensureAccount(_ref)) return;
    if (follow) {
      await _api.forumControllerFollow(id: threadId);
    } else {
      await _api.forumControllerUnfollow(id: threadId);
    }
    await _ref.read(forumMessagesProvider(threadId).notifier).refresh();
  }

  Future<void> setPin(String threadId, String messageId, bool pinned) async {
    if (pinned) {
      await _moderation.moderationControllerPin(id: messageId);
    } else {
      await _moderation.moderationControllerUnpin(id: messageId);
    }
    await _ref.read(forumMessagesProvider(threadId).notifier).refresh();
  }

  Future<void> react(String threadId, ForumMessageDto message, PutReactionDtoEmojiEnum emoji) async {
    if (!await ensureAccount(_ref)) return;
    final notifier = _ref.read(forumMessagesProvider(threadId).notifier);
    final remove = message.myReaction == emoji.name;
    notifier.showReaction(message.id, emoji.name, remove: remove);
    try {
      if (remove) {
        await _api.forumControllerDeleteReaction(id: message.id);
      } else {
        await _api.forumControllerPutReaction(id: message.id, putReactionDto: PutReactionDto((b) => b..emoji = emoji));
      }
    } catch (_) {
      // Échec : on remet l'affichage du serveur avant de signaler l'erreur.
      await notifier.refresh().catchError((_) {});
      rethrow;
    }
    await notifier.refresh();
  }

  Future<void> report(String threadId, String messageId, ReportMessageDtoReasonEnum reason) async {
    if (!await ensureAccount(_ref)) return;
    await _api.forumControllerReport(id: messageId, reportMessageDto: ReportMessageDto((b) => b..reason = reason));
    await _ref.read(forumMessagesProvider(threadId).notifier).refresh();
  }

  Future<void> deleteMessage(String threadId, String messageId) async {
    await _api.forumControllerDeleteMessage(id: messageId);
    await _ref.read(forumMessagesProvider(threadId).notifier).refresh();
    _ref.invalidate(forumThreadsProvider);
    _ref.invalidate(forumThreadProvider);
  }

  Future<void> block(String threadId, String userId) async {
    if (!await ensureAccount(_ref)) return;
    await _api.forumControllerBlock(userId: userId);
    _ref.invalidate(forumBlocksProvider);
    await _ref.read(forumMessagesProvider(threadId).notifier).refresh();
    showUndo("Utilisateur bloqué.", () async {
      await unblock(userId);
      await _ref.read(forumMessagesProvider(threadId).notifier).refresh();
    });
  }

  Future<void> unblock(String userId) async {
    await _api.forumControllerUnblock(userId: userId);
    _ref.invalidate(forumBlocksProvider);
  }

  Future<ForumThreadDto> createThread(String title, {String? game}) async {
    final thread = (await _api.forumControllerCreateThread(
      createThreadDto: CreateThreadDto((b) {
        b.title = title;
        if (game != null) b.game = game;
      }),
    )).data!;
    _ref.invalidate(forumThreadsProvider);
    return thread;
  }

  Future<void> setCamp(String game, String entityId) async {
    await _api.forumControllerPutCamp(putCampDto: PutCampDto((b) => b..game = game..entityId = entityId));
    _ref.invalidate(forumCampsProvider);
  }

  Future<void> clearCamp(String game) async {
    await _api.forumControllerDeleteCamp(game: game);
    _ref.invalidate(forumCampsProvider);
  }

  // ---- Modération ----

  ModerationApi get _moderation => _ref.read(apiClientProvider).getModerationApi();

  Future<void> dismissReports(String messageId) async {
    await _moderation.moderationControllerDismiss(id: messageId);
    _ref.invalidate(moderationReportsProvider);
  }

  Future<void> hideMessage(String messageId) async {
    await _moderation.moderationControllerHide(id: messageId);
    _ref.invalidate(moderationReportsProvider);
  }

  Future<void> setBan(String userId, {required bool banned}) async {
    if (banned) {
      await _moderation.moderationControllerBan(userId: userId);
    } else {
      await _moderation.moderationControllerUnban(userId: userId);
    }
  }

  Future<void> setLock(String threadId, {required bool locked}) async {
    if (locked) {
      await _moderation.moderationControllerLock(id: threadId);
    } else {
      await _moderation.moderationControllerUnlock(id: threadId);
    }
    _ref.invalidate(forumThreadsProvider);
  }
}

final forumControllerProvider = Provider((ref) => ForumController(ref));

/// Message lisible d'une erreur du forum : texte du serveur s'il y en a un, sinon générique.
String forumErrorMessage(Object error) => apiErrorMessage(error) ?? accountErrorMessage(error);
