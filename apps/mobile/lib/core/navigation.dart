import "package:flutter_riverpod/flutter_riverpod.dart";

/// Onglet courant de la tab bar (`app.dart`) : partagé pour qu'un écran (l'icône
/// de recherche de l'Accueil, J10) puisse en ouvrir un autre.
class TabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final tabIndexProvider = NotifierProvider<TabIndexNotifier, int>(TabIndexNotifier.new);

const competitionsTabIndex = 2;

/// Compteur incrémenté à chaque demande de "mets le curseur dans la recherche"
/// de l'onglet Compétitions.
class SearchFocusRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final searchFocusRequestProvider = NotifierProvider<SearchFocusRequestNotifier, int>(SearchFocusRequestNotifier.new);
