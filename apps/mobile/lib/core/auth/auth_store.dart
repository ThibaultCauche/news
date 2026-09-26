import "dart:math";

import "package:shared_preferences/shared_preferences.dart";

const _accessTokenKey = "auth.accessToken";
const _refreshTokenKey = "auth.refreshToken";
const _installIdKey = "device.installId";

/// Jetons du compte anonyme et identifiant d'installation, en clair dans
/// `shared_preferences` (docs/04 J4) : le compte est anonyme, sans donnée
/// personnelle, un stockage sécurisé n'apporterait rien ici.
class AuthStore {
  AuthStore(this._prefs);

  final SharedPreferences _prefs;

  String? get accessToken => _prefs.getString(_accessTokenKey);
  String? get refreshToken => _prefs.getString(_refreshTokenKey);

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _prefs.setString(_accessTokenKey, accessToken);
    await _prefs.setString(_refreshTokenKey, refreshToken);
  }

  Future<void> saveAccessToken(String accessToken) => _prefs.setString(_accessTokenKey, accessToken);

  Future<void> clear() async {
    await _prefs.remove(_accessTokenKey);
    await _prefs.remove(_refreshTokenKey);
  }

  // Généré une fois, persiste tant que l'appli n'est pas désinstallée — la clé
  // de `PUT /v1/devices/me` (docs/04 J4), pas de dépendance `uuid` pour ça.
  String get installId {
    final existing = _prefs.getString(_installIdKey);
    if (existing != null) return existing;
    final random = Random.secure();
    final generated = List<int>.generate(16, (_) => random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, "0")).join();
    _prefs.setString(_installIdKey, generated);
    return generated;
  }
}
