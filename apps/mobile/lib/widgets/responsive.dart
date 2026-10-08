import "package:flutter/material.dart";
import "../theme/tokens.dart";

/// Largeur à partir de laquelle l'appli passe en mode ordinateur (J17) : rail de navigation à gauche, pages en colonnes.
/// En dessous, la mise en page téléphone reste inchangée.
const kWideBreakpoint = 900.0;

/// Largeur maximale du contenu d'un écran ouvert par-dessus un onglet en mode ordinateur (réglages, profil, tutos…).
const kPageMaxWidth = 760.0;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= kWideBreakpoint;

/// Transition de page qui, en mode ordinateur, centre l'écran poussé dans une colonne de [kPageMaxWidth] : un écran
/// pensé pour un téléphone n'a pas à s'étirer sur 1 200 px. Un écran qui a sa propre mise en page large s'ouvre avec
/// [wideRoute].
class WidePageTransitions extends PageTransitionsBuilder {
  const WidePageTransitions(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final constrain = isWide(context) && !route.isFirst && route.settings.name != wideRouteName;
    return inner.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      constrain
          ? ColoredBox(
              color: AppColors.background,
              child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kPageMaxWidth), child: child)),
            )
          : child,
    );
  }
}

const wideRouteName = "wide";

/// Route d'un écran qui gère lui-même les grands écrans (pas de colonne imposée).
Route<T> wideRoute<T>(WidgetBuilder builder) => MaterialPageRoute<T>(settings: const RouteSettings(name: wideRouteName), builder: builder);
