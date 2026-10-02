import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../core/auth/account.dart";
import "../theme/tokens.dart";
import "empty_mark.dart";

/// Échec d'une action (bouton) : message français en bas d'écran, jamais le texte brut de l'erreur.
void showErrorSnackBar(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(error) ?? accountErrorMessage(error))));
}

/// Bloc de remplissage d'un skeleton (J15) : laiton très atténué, **sans animation** (règle 13 :
/// ce qu'on voit plusieurs fois par jour ne bouge pas).
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height = 16, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.brass.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(radius)),
    );
  }
}

/// Gabarit par défaut : une pile de cartes arrondies de la hauteur d'une carte de match.
/// Les écrans aux mises en page très différentes passent leur propre `skeleton` à [AsyncView].
class SkeletonCards extends StatelessWidget {
  const SkeletonCards({super.key, this.count = 4, this.height = 96, this.padding = const EdgeInsets.all(AppSpacing.md)});

  final int count;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // Dans une zone de hauteur limitée, seulement les cartes qui tiennent (pas de débordement).
        var shown = count;
        if (box.hasBoundedHeight) {
          final available = box.maxHeight - padding.resolve(Directionality.of(context)).vertical;
          shown = ((available + AppSpacing.cardGap) / (height + AppSpacing.cardGap)).floor().clamp(0, count);
        }
        return Padding(
          padding: padding,
          child: ExcludeSemantics(
            child: Column(
              children: [
                for (var i = 0; i < shown; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.cardGap),
                  Skeleton(height: height, radius: AppRadii.card),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Erreur de chargement (J15) : un message en français qui dit quoi faire, jamais de code ni de
/// texte brut, et un bouton « Réessayer ». `compact` pour une feuille ou une carte (sans monogramme).
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, this.message = "Impossible de charger cette page.", required this.onRetry, this.compact = false});

  final String message;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final retry = TextButton(onPressed: onRetry, child: const Text("Réessayer"));
    if (compact) {
      return Column(mainAxisSize: MainAxisSize.min, children: [Text(message, style: const TextStyle(color: AppColors.textSecondary)), retry]);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyMark("$message\nVérifie ta connexion, puis réessaie."),
            const SizedBox(height: AppSpacing.sm),
            retry,
          ],
        ),
      ),
    );
  }
}

/// Lance une action de bouton : si elle échoue, message français au lieu d'une erreur silencieuse.
Future<void> runOrShowError(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e) ?? accountErrorMessage(e))));
  }
}

/// Un seul `switch` pour tous les écrans : contenu dès qu'une valeur existe (y compris pendant un
/// rechargement automatique ou après un échec de rechargement : `AutoRefresh` invalide les
/// providers chaque minute, un skeleton ne doit pas réapparaître), skeleton pendant le premier
/// chargement, [ErrorState] seulement s'il n'y a rien à montrer.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    required this.onRetry,
    this.errorMessage = "Impossible de charger cette page.",
    this.skeleton = const SkeletonCards(),
    this.compactError = false,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;
  final String errorMessage;
  final Widget skeleton;
  final bool compactError;

  @override
  Widget build(BuildContext context) {
    final (state, child) = value.hasValue
        ? ("data", builder(value.value as T))
        : value.hasError
            ? ("error", ErrorState(message: errorMessage, onRetry: onRetry, compact: compactError))
            // Un seul libellé pour les lecteurs d'écran : les blocs gris n'ont rien à dire.
            : ("loading", Semantics(label: "Chargement en cours", container: true, child: ExcludeSemantics(child: skeleton)));
    // Fondu court (opacité seule, règle 13) quand le skeleton laisse place au contenu ; rien en
    // mouvement réduit, et rien pour les rechargements (même état « data »).
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
      layoutBuilder: (current, previous) => Stack(fit: StackFit.passthrough, alignment: Alignment.topCenter, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey(state), child: child),
    );
  }
}
