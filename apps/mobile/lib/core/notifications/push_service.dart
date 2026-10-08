import "package:flutter/foundation.dart" show kIsWeb;
import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../api_providers.dart";
import "../auth/auth_store.dart";

/// Enregistre l'appareil pour les notifications push (docs/03 §4/§6, docs/04
/// J4) : demande la permission puis `PUT /v1/devices/me`. Appelé au premier
/// "Suivre"/"M'alerter" plutôt qu'au lancement (permission "au bon moment",
/// docs/04 J4). Android uniquement pour l'instant (iOS reporté après la
/// sortie de l'appli). Échoue sans bruit tant que le projet Firebase n'est
/// pas relié côté appli (`google-services.json` pas encore ajouté) : l'appli
/// reste utilisable sans push, comme le reste du mode hors ligne d'abord.
class PushService {
  PushService(this._api, this._auth);

  final NewsApiClient _api;
  final AuthStore _auth;
  bool _registered = false;

  Future<void> ensureRegistered() async {
    // Pas de push sur le web pour l'instant (service worker et clé VAPID : décision du J17).
    if (_registered || kIsWeb) return;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken();

      await _api.getDevicesApi().devicesControllerPutMe(
        putDeviceDto: PutDeviceDto(
          (b) => b
            ..installId = _auth.installId
            ..platform = PutDeviceDtoPlatformEnum.android
            ..pushToken = token
            ..utcOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes,
        ),
      );
      _registered = true;
    } catch (_) {
      // Firebase pas encore configuré côté appli, permission refusée, ou
      // réseau indisponible : rien à faire de plus, on retentera au prochain
      // "Suivre".
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(ref.watch(apiClientProvider), ref.watch(authStoreProvider));
});
