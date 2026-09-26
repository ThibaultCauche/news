import "package:flutter/material.dart";

/// Grand titre de page (`docs/maquettes/specs/commun.md` — style `display`,
/// 34/700/−2,5 %). Un par écran, en général suivi de `PageSubtitle`.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.headlineLarge);
  }
}
