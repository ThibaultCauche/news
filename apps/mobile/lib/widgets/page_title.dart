import "package:flutter/material.dart";
import "../theme/app_theme.dart";

/// Grand titre de page (`docs/maquettes/specs/commun.md` — style `display`,
/// Cinzel 34/700, J16). Un par écran, en général suivi de `PageSubtitle`.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.pageTitle);
  }
}
