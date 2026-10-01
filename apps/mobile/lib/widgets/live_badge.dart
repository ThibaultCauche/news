import "dart:math";
import "package:flutter/material.dart";
import "../theme/tokens.dart";
import "live_dot.dart";

/// Tampon (J16) : capitales Cinzel dans un cadre fin, légèrement incliné,
/// pour « EN DIRECT », « TERMINÉ »… Statique.
class Stamp extends StatelessWidget {
  const Stamp(this.text, {super.key, this.color = AppColors.live, this.dot = false, this.fontSize = 11});

  final String text;
  final Color color;
  final bool dot;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -2 * pi / 180,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.85), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot) ...[LiveDot(size: 6, color: color), const SizedBox(width: 6)],
              Text(
                text,
                style: TextStyle(fontFamily: "Cinzel", fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: fontSize * 0.12, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Badge « EN DIRECT » / « CHAMPIONS · ICI » : un [Stamp] avec point animé.
class LiveBadge extends StatelessWidget {
  const LiveBadge(this.text, {super.key, this.color = AppColors.live});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Stamp(text, color: color, dot: true);
}
