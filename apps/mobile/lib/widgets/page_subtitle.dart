import "package:flutter/material.dart";
import "../theme/tokens.dart";

/// Sous-titre de page (`docs/maquettes/specs/commun.md` — style `bodyLarge`,
/// 15/400/−0,6 %, blanc 55 %). Juste sous `PageTitle`, ou juste au-dessus
/// (écran Accueil : la date précède "Aujourd'hui").
class PageSubtitle extends StatelessWidget {
  const PageSubtitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary));
  }
}
