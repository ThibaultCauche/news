import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../features/account/account_gate.dart";
import "api_providers.dart";
import "auth/account.dart";

/// Réglages (écran 22, `docs/04` J6) : sans spoil (global — une seule vraie
/// catégorie avec des données pour l'instant, la granularité par catégorie de la
/// maquette attendra une 2e catégorie), résumé du matin (réglage seul, pas
/// encore envoyé), heures calmes.
final userSettingProvider = FutureProvider.autoDispose<UserSettingDto>((ref) async {
  // Invité : réglages par défaut (sans spoil désactivé), modifiables seulement avec un compte.
  if (!ref.watch(signedInProvider)) return UserSettingDto((b) => b..spoilerFree = false..morningDigest = false..notifyForumReplies = true..notifyForumThreads = true..notifyMatchReminder = true..notifyMatchStart = true..notifyMatchResult = true..notifyQualification = true..notifyPredictionReminders = true);
  final response = await ref.watch(apiClientProvider).getMeApi().meControllerGetSettings();
  return response.data!;
});

class SettingsController {
  SettingsController(this._ref);

  final Ref _ref;

  Future<void> update({bool? spoilerFree, bool? morningDigest, bool? notifyForumReplies, bool? notifyForumThreads, bool? notifyMatchReminder, bool? notifyMatchStart, bool? notifyMatchResult, bool? notifyQualification, bool? notifyPredictionReminders, int? quietHoursStart, int? quietHoursEnd}) async {
    if (!await ensureAccount(_ref)) return;
    await _ref.read(apiClientProvider).getMeApi().meControllerUpdateSettings(
      updateUserSettingDto: UpdateUserSettingDto((b) {
        if (spoilerFree != null) b.spoilerFree = spoilerFree;
        if (morningDigest != null) b.morningDigest = morningDigest;
        if (notifyForumReplies != null) b.notifyForumReplies = notifyForumReplies;
        if (notifyForumThreads != null) b.notifyForumThreads = notifyForumThreads;
        if (notifyMatchReminder != null) b.notifyMatchReminder = notifyMatchReminder;
        if (notifyMatchStart != null) b.notifyMatchStart = notifyMatchStart;
        if (notifyMatchResult != null) b.notifyMatchResult = notifyMatchResult;
        if (notifyQualification != null) b.notifyQualification = notifyQualification;
        if (notifyPredictionReminders != null) b.notifyPredictionReminders = notifyPredictionReminders;
        if (quietHoursStart != null) b.quietHoursStart = quietHoursStart;
        if (quietHoursEnd != null) b.quietHoursEnd = quietHoursEnd;
      }),
    );
    // On attend le rechargement : l'interrupteur ne repasse à la valeur serveur qu'une fois à jour.
    _ref.invalidate(userSettingProvider);
    await _ref.read(userSettingProvider.future);
  }
}

final settingsControllerProvider = Provider((ref) => SettingsController(ref));

/// Taille des tuiles de match (`EventCard`) : réglage local (`AuthStore`,
/// `shared_preferences`), pas envoyé au serveur — `Notifier` plutôt qu'une
/// simple lecture directe pour que le bouton des Réglages fasse réagir
/// toutes les tuiles déjà affichées ailleurs dans l'appli, immédiatement.
class CompactEventCardsNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(authStoreProvider).compactEventCards;

  Future<void> set(bool value) async {
    await ref.read(authStoreProvider).setCompactEventCards(value);
    state = value;
  }
}

final compactEventCardsProvider = NotifierProvider<CompactEventCardsNotifier, bool>(CompactEventCardsNotifier.new);

/// Logo de l'équipe dans les notifications (Réglages) : local à l'appareil, comme `CompactEventCardsNotifier`.
class NotificationTeamLogoNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(authStoreProvider).notificationTeamLogo;

  Future<void> set(bool value) async {
    await ref.read(authStoreProvider).setNotificationTeamLogo(value);
    state = value;
  }
}

final notificationTeamLogoProvider = NotifierProvider<NotificationTeamLogoNotifier, bool>(NotificationTeamLogoNotifier.new);
