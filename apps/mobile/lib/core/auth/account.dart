import "package:dio/dio.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart" show debugPrint;
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../api_providers.dart";

/// Connecté ou invité (docs/04 J11) : l'invité navigue en lecture seule, sans compte ni jeton ;
/// tout le reste (suivre, alertes, favoris, réglages, pronostics) exige d'être connecté.
/// Les providers qui appellent une route authentifiée surveillent celui-ci et rendent du
/// vide pour un invité, puis se rechargent à la connexion.
class SignedInNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(authStoreProvider).accessToken != null;

  void set(bool value) => state = value;
}

final signedInProvider = NotifierProvider<SignedInNotifier, bool>(SignedInNotifier.new);

/// Compte Firebase Auth (e-mail + mot de passe) échangé contre nos JWT (`POST /v1/auth/firebase`).
/// Firebase envoie lui-même l'e-mail de vérification et celui de réinitialisation.
class AccountService {
  AccountService(this._ref);

  final Ref _ref;

  FirebaseAuth get _firebase => FirebaseAuth.instance;

  String? get email => _firebase.currentUser?.email;
  bool get emailVerified => _firebase.currentUser?.emailVerified ?? false;

  Future<void> signUp(String email, String password) async {
    final credential = await _firebase.createUserWithEmailAndPassword(email: email, password: password);
    await credential.user?.sendEmailVerification();
    await _exchange();
  }

  Future<void> signIn(String email, String password) async {
    await _firebase.signInWithEmailAndPassword(email: email, password: password);
    await _exchange();
  }

  Future<void> sendPasswordReset(String email) => _firebase.sendPasswordResetEmail(email: email);

  Future<void> resendVerification() async => _firebase.currentUser?.sendEmailVerification();

  /// Après le clic sur le lien de l'e-mail : recharge l'utilisateur Firebase et se reconnecte
  /// à notre API pour qu'elle voie `emailVerified` (nécessaire pour créer un pseudo).
  Future<bool> refreshVerification() async {
    await _firebase.currentUser?.reload();
    if (_firebase.currentUser == null) return false;
    await _exchange();
    return emailVerified;
  }

  Future<void> signOut() async {
    await _firebase.signOut();
    await _clearLocalSession();
  }

  /// RGPD : l'API supprime le compte, ses données et l'utilisateur Firebase.
  Future<void> deleteAccount() async {
    await _ref.read(apiClientProvider).getMeApi().meControllerDeleteAccount();
    await _firebase.signOut().catchError((_) {});
    await _clearLocalSession();
  }

  Future<void> _exchange() async {
    final idToken = await _firebase.currentUser!.getIdToken(true);
    // `Dio` nu, sans intercepteur : cet appel n'a rien à envoyer ni à mettre en cache.
    final api = NewsApiClient(dio: Dio(BaseOptions(baseUrl: resolveApiBaseUrl())));
    final tokens = (await api.getAuthApi().authControllerLoginWithFirebase(firebaseLoginDto: FirebaseLoginDto((b) => b..idToken = idToken!))).data!;
    await _ref.read(authStoreProvider).saveTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
    _ref.read(signedInProvider.notifier).set(true);
  }

  Future<void> _clearLocalSession() async {
    await _ref.read(authStoreProvider).clear();
    await _ref.read(cacheStoreProvider).clear();
    _ref.read(signedInProvider.notifier).set(false);
  }
}

final accountServiceProvider = Provider((ref) => AccountService(ref));

/// Texte français d'une erreur de connexion (codes Firebase Auth, erreurs réseau).
String accountErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      "invalid-email" => "Adresse e-mail invalide.",
      "user-disabled" => "Ce compte est désactivé.",
      "user-not-found" || "wrong-password" || "invalid-credential" => "E-mail ou mot de passe incorrect.",
      "email-already-in-use" => "Un compte existe déjà avec cet e-mail.",
      "weak-password" => "Mot de passe trop court (6 caractères minimum).",
      "too-many-requests" => "Trop de tentatives, réessaie dans quelques minutes.",
      "network-request-failed" => "Pas de connexion. Réessaie une fois en ligne.",
      _ => _unknown(error),
    };
  }
  if (error is DioException) {
    return switch (error.response?.statusCode) {
      null => "Pas de connexion au serveur. Vérifie ton réseau puis réessaie.",
      401 => "Ta session a expiré. Reconnecte-toi.",
      429 => "Trop de demandes. Réessaie dans un instant.",
      >= 500 => "Le service a un souci. Réessaie dans un instant.",
      _ => _unknown(error),
    };
  }
  return _unknown(error);
}

/// L'erreur réelle est journalisée, jamais affichée (J15).
String _unknown(Object error) {
  debugPrint("Erreur : $error");
  return "Une erreur est survenue. Réessaie.";
}

/// Message d'une erreur métier de l'API, ou `null`. Seuls les statuts de refus voulus par nos
/// services (400, 403, 404, 409) portent un texte français à montrer ; les erreurs génériques de
/// NestJS (401, 429, 5xx, validation) restent anglaises ou techniques : on laisse `accountErrorMessage`.
String? apiErrorMessage(Object error) {
  if (error is DioException && const {400, 403, 404, 409}.contains(error.response?.statusCode)) {
    final data = error.response?.data;
    if (data is Map && data["message"] is String) return data["message"] as String;
  }
  return null;
}

/// Code d'erreur métier de l'API (ex. `PSEUDO_TAKEN`), ou `null`.
String? apiErrorCode(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data["code"] is String) return data["code"] as String;
  }
  return null;
}
