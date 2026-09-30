import "package:flutter_riverpod/flutter_riverpod.dart";

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Date du jour, sans l'heure. Écrans qui en dépendent (Agenda, en-tête de l'Accueil) la
/// surveillent : elle est remise à jour par `AutoRefresh` (retour au premier plan, minuterie),
/// donc une app laissée ouverte toute la nuit change de jour sans être relancée.
class TodayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => dateOnly(DateTime.now());

  void sync() {
    final now = dateOnly(DateTime.now());
    if (now != state) state = now;
  }
}

final todayProvider = NotifierProvider<TodayNotifier, DateTime>(TodayNotifier.new);
