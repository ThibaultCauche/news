import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "api_providers.dart";

/// Réglages (écran 22, `docs/04` J6) : sans spoil (global — une seule vraie
/// catégorie avec des données pour l'instant, la granularité par catégorie de la
/// maquette attendra une 2e catégorie), résumé du matin (réglage seul, pas
/// encore envoyé), heures calmes.
final userSettingProvider = FutureProvider.autoDispose<UserSettingDto>((ref) async {
  final response = await ref.watch(apiClientProvider).getMeApi().meControllerGetSettings();
  return response.data!;
});

class SettingsController {
  SettingsController(this._ref);

  final Ref _ref;

  Future<void> update({bool? spoilerFree, bool? morningDigest, int? quietHoursStart, int? quietHoursEnd}) async {
    await _ref.read(apiClientProvider).getMeApi().meControllerUpdateSettings(
      updateUserSettingDto: UpdateUserSettingDto((b) {
        if (spoilerFree != null) b.spoilerFree = spoilerFree;
        if (morningDigest != null) b.morningDigest = morningDigest;
        if (quietHoursStart != null) b.quietHoursStart = quietHoursStart;
        if (quietHoursEnd != null) b.quietHoursEnd = quietHoursEnd;
      }),
    );
    _ref.invalidate(userSettingProvider);
  }
}

final settingsControllerProvider = Provider((ref) => SettingsController(ref));
