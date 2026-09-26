import "dart:math" as math;

import "package:flutter/material.dart";
import "../theme/tokens.dart";

enum SeasonStepKind { done, current, upcoming }

/// Une étape de la frise de saison (`docs/maquettes/specs/01-valorant-saison.md`).
class SeasonStep {
  const SeasonStep({required this.label, required this.kind, this.milestone = false});

  final String label;
  final SeasonStepKind kind;

  /// Étape majeure (Masters…) : losange plus grand plutôt qu'un petit point.
  final bool milestone;
}

/// Frise horizontale "où on en est" (`docs/maquettes/specs/01-valorant-saison.md`) :
/// une ligne de points reliés, l'étape en cours cerclée de rouge, labels
/// dessous.
class SeasonTimeline extends StatelessWidget {
  const SeasonTimeline({super.key, required this.steps});

  final List<SeasonStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 24,
          child: Row(
            children: [
              for (final (i, step) in steps.indexed) ...[
                _Dot(step: step),
                if (i != steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: Colors.white.withValues(alpha: step.kind == SeasonStepKind.upcoming ? 0.08 : 0.3),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final step in steps)
              Expanded(
                child: Text(
                  step.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: "Inter",
                    fontSize: 10,
                    color: AppColors.textPrimary.withValues(
                      alpha: step.kind == SeasonStepKind.upcoming ? 0.3 : 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.step});

  final SeasonStep step;

  @override
  Widget build(BuildContext context) {
    final size = step.milestone ? 13.0 : 8.0;
    final color = switch (step.kind) {
      SeasonStepKind.done => Colors.white.withValues(alpha: 0.85),
      SeasonStepKind.current => AppColors.live,
      SeasonStepKind.upcoming => Colors.white.withValues(alpha: 0.3),
    };
    Widget dot = step.milestone
        ? Transform.rotate(angle: math.pi / 4, child: Container(width: size, height: size, color: color))
        : Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    if (step.kind == SeasonStepKind.current) {
      dot = Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AppColors.live, width: 2))),
        child: dot,
      );
    } else {
      dot = SizedBox(width: 24, height: 24, child: Center(child: dot));
    }
    return dot;
  }
}
