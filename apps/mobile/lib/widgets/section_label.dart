import "package:flutter/material.dart";
import "../theme/tokens.dart";

/// Libellé de section en petites capitales (`docs/maquettes/specs/commun.md`
/// — style `eyebrow`, 12/600/+4 %, blanc 50 %). Ex. "SAISON 2026", "TOUR 1".
/// Le texte doit déjà être en majuscules côté appelant (pas de `toUpperCase`
/// automatique : certains libellés mélangent capitales et suffixe, ex.
/// "TOUR 1 · terminé").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.brass));
  }
}
