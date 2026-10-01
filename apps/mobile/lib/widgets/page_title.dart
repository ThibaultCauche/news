import "package:flutter/material.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";

/// Filet laiton pleine largeur (J16) : deux traits qui s'effacent vers les bords, un
/// losange au centre.
class BrassRule extends StatelessWidget {
  const BrassRule({super.key});

  @override
  Widget build(BuildContext context) {
    Widget line(bool fadeLeft) => Expanded(
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: fadeLeft ? [Colors.transparent, AppColors.brass] : [AppColors.brass, Colors.transparent],
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: Row(
        children: [
          line(true),
          const SizedBox(width: AppSpacing.sm),
          Transform.rotate(angle: 0.7854, child: const SizedBox(width: 6, height: 6, child: ColoredBox(color: AppColors.brass))),
          const SizedBox(width: AppSpacing.sm),
          line(false),
        ],
      ),
    );
  }
}

/// Grand titre de page (Cinzel 34/700 en laiton, J16), souligné d'un [BrassRule] centré sur
/// toute la largeur. Un par écran, en général suivi de `PageSubtitle`.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, style: AppTextStyles.pageTitle),
        const SizedBox(height: 6),
        const BrassRule(),
      ],
    );
  }
}
