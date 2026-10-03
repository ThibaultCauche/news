import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../features/competitions/competitions_data.dart";
import "../theme/tokens.dart";
import "async_view.dart";

/// L'étoile d'une page compétition (J20) : la met dans « Favoris » de l'onglet Compétitions, pour la
/// retrouver en un geste. Un raccourci seulement : pas d'alerte (c'est le rôle de « Suivre »).
class CompetitionFavoriteButton extends ConsumerWidget {
  const CompetitionFavoriteButton({super.key, required this.competitionId, required this.name});

  final String competitionId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorite = (ref.watch(favoriteCompetitionsProvider).value ?? const []).any((f) => f.id == competitionId);
    return IconButton(
      tooltip: favorite ? "Retirer des favoris" : "Ajouter aux favoris",
      icon: Icon(favorite ? Icons.star_rounded : Icons.star_border_rounded, color: favorite ? AppColors.brass : AppColors.textSecondary),
      onPressed: () => runOrShowError(context, () => ref.read(favoriteCompetitionsProvider.notifier).toggle(competitionId, name: name)),
    );
  }
}
