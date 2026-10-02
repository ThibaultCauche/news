import "package:flutter_riverpod/flutter_riverpod.dart";

/// `null` : en ligne. Sinon l'heure des données en cache affichées à la place de l'API (J18) :
/// alimente le bandeau « Hors ligne » (`widgets/offline_banner.dart`).
class OfflineNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void markOffline(DateTime dataFrom) => state = dataFrom;

  void markOnline() {
    if (state != null) state = null;
  }
}

final offlineProvider = NotifierProvider<OfflineNotifier, DateTime?>(OfflineNotifier.new);
