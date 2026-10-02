import "package:flutter_riverpod/flutter_riverpod.dart";

/// `null` : en ligne. Sinon l'heure de la dernière connexion réussie (J18, J19) : alimente le bandeau
/// « Hors ligne » (`widgets/offline_banner.dart`). Une seule heure, figée tant qu'on reste hors ligne :
/// chaque page a son propre cache, afficher l'heure de celui qu'on lit faisait varier le bandeau d'un écran à l'autre.
class OfflineNotifier extends Notifier<DateTime?> {
  DateTime? _lastOnline;

  @override
  DateTime? build() => null;

  /// `dataFrom` (heure du cache lu) ne sert que si on n'a jamais été en ligne depuis le lancement.
  void markOffline(DateTime dataFrom) => state ??= _lastOnline ?? dataFrom;

  void markOnline() {
    _lastOnline = DateTime.now();
    if (state != null) state = null;
  }
}

final offlineProvider = NotifierProvider<OfflineNotifier, DateTime?>(OfflineNotifier.new);
