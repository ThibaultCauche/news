import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "../theme/app_theme.dart";

/// Grand titre de page (Cinzel 34/700 en laiton, J16), souligné d'un filet à
/// losange. Un par écran, en général suivi de `PageSubtitle`.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: AppTextStyles.pageTitle),
        const SizedBox(height: 4),
        ExcludeSemantics(child: SvgPicture.asset("assets/ornaments/rule.svg", width: 120)),
      ],
    );
  }
}
