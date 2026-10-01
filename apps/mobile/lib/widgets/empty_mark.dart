import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "../theme/tokens.dart";

/// Écran ou zone vide (J16) : le monogramme Keryx, atténué, au-dessus du message.
class EmptyMark extends StatelessWidget {
  const EmptyMark(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(opacity: 0.55, child: ExcludeSemantics(child: SvgPicture.asset("assets/ornaments/monogram.svg", width: 44, height: 44))),
        const SizedBox(height: AppSpacing.sm),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }
}
