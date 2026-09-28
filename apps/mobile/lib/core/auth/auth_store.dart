import "dart:math";

import "package:shared_preferences/shared_preferences.dart";

const _accessTokenKey = "auth.accessToken";
const _refreshTokenKey = "auth.refreshToken";
const _installIdKey = "device.installId";
const _onboardingSeenKey = "onboarding.seen";
const _compactEventCardsKey = "display.compactEventCards";
const _agendaCategoryKey = "agenda.category";
const _agendaLeagueIdsKey = "agenda.leagueIds";

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

  // Onboarding (écrans 11-12, J6) : montré une seule fois, "Passer" a le même
  // effet que "C'est parti" (docs/02 — le choix des sujets n'est pas encore
  // bloquant tant qu'une seule catégorie a de vraies données).
  bool get hasSeenOnboarding => _prefs.getBool(_onboardingSeenKey) ?? false;

  Future<void> markOnboardingSeen() => _prefs.setBool(_onboardingSeenKey, true);

  // Taille des tuiles de match (`EventCard`) : préférence d'affichage pure,
  // propre à l'appareil — pas de raison de la faire voyager sur le compte.
  bool get compactEventCards => _prefs.getBool(_compactEventCardsKey) ?? false;

  Future<void> setCompactEventCards(bool value) => _prefs.setBool(_compactEventCardsKey, value);

  // Filtre de l'Agenda (catégorie + ligues e-sport cochées) : là aussi une
  // préférence d'affichage propre à l'appareil, pas un réglage de compte —
  // pour ne pas rouvrir sur "Tout" à chaque lancement (J8).
  String? get agendaCategory => _prefs.getString(_agendaCategoryKey);
  String? get agendaLeagueIds => _prefs.getString(_agendaLeagueIdsKey);

  Future<void> setAgendaFilter({String? category, String? leagueIds}) async {
    if (category == null) {
      await _prefs.remove(_agendaCategoryKey);
    } else {
      await _prefs.setString(_agendaCategoryKey, category);
    }
    if (leagueIds == null) {
      await _prefs.remove(_agendaLeagueIdsKey);
    } else {
      await _prefs.setString(_agendaLeagueIdsKey, leagueIds);
    }
  }
}
