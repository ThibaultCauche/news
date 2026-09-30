import "package:flutter/material.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";

/// Avatar rond (J11) : le logo de l'équipe choisie, sinon l'initiale du pseudo, sinon une
/// silhouette (invité). Pas d'envoi de photo : ni stockage, ni modération d'images.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({super.key, this.avatarUrl, this.pseudo, this.radius = 18});

  final String? avatarUrl;
  final String? pseudo;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    if (avatarUrl != null) {
      // Logo sur pastille claire (les logos d'équipe sont pensés pour un fond clair), entier et
      // centré avec une marge : `contain` plutôt que `cover`, sinon les logos larges débordent
      // du cercle et sont rognés.
      return Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(radius * 0.22),
        decoration: const BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle),
        child: Image.network(avatarUrl!, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
      );
    }
    final Widget child = pseudo != null && pseudo!.isNotEmpty
        ? Text(pseudo![0].toUpperCase(), style: AppTextStyles.cardTitle.copyWith(fontSize: radius * 0.9))
        : Icon(Icons.person_outline_rounded, size: radius * 1.1, color: AppColors.textSecondary);
    return CircleAvatar(radius: radius, backgroundColor: AppColors.surface, child: child);
  }
}
