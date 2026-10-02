import "package:flutter/material.dart";
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

/// Clé du `ScaffoldMessenger` racine : permet d'afficher une barre de message depuis un contrôleur,
/// sans `BuildContext` (J18, bouton « Annuler »).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Barre de message avec « Annuler » (5 s) : arrêter de suivre ou bloquer ne demande aucune
/// confirmation préalable, mais se défait d'un geste. Une erreur d'annulation est ignorée.
void showUndo(String message, Future<void> Function() undo) {
  scaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        // Une barre avec une action ne se ferme pas toute seule par défaut (accessibilité) ; ici elle doit.
        persist: false,
        action: SnackBarAction(label: "Annuler", onPressed: () => undo().catchError((_) {})),
      ),
    );
}
