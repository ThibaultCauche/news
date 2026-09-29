import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "../theme/tokens.dart";

/// Logo d'un jeu : fichier embarqué `assets/games/<slug>.svg` (PandaScore ne
/// fournit aucun logo de jeu, seulement des logos de ligues). Icône de manette
/// tant que le fichier du jeu n'a pas été ajouté.
class GameLogo extends StatelessWidget {
  const GameLogo({super.key, required this.slug, this.size = 32});

  final String slug;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.sports_esports_outlined, size: size * 0.6, color: AppColors.textSecondary);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.chip)),
      clipBehavior: Clip.antiAlias,
      child: SvgPicture.asset("assets/games/$slug.svg", fit: BoxFit.contain, errorBuilder: (_, _, _) => Center(child: fallback)),
    );
  }
}

/// Logo d'une ligue (fourni par le fournisseur, souvent prévu pour fond clair :
/// d'où la pastille claire, invisible sinon sur le thème sombre).
class LeagueLogo extends StatelessWidget {
  const LeagueLogo({super.key, required this.imageUrl, this.size = 32});

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.emoji_events_outlined, size: size * 0.6, color: AppColors.textSecondary);
    final url = imageUrl;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(color: url == null ? AppColors.surface : AppColors.textPrimary, borderRadius: BorderRadius.circular(AppRadii.chip)),
      clipBehavior: Clip.antiAlias,
      child: url == null ? fallback : Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => fallback),
    );
  }
}
