import "package:flutter/material.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";

/// Contrôle segmenté (`docs/maquettes/specs/commun.md`,
/// `01-valorant-saison.md`) : piste 358×34 rx=10 blanc 8 %, pastille active
/// 88,5×30 rx=8 blanc 16 % (marge ≈2 px), libellés 13/600 blanc plein
/// (actif) ou 13/500 blanc 60 % (inactif).
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({super.key, required this.labels, required this.selectedIndex, required this.onChanged});

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentWidth = constraints.maxWidth / labels.length;
        return SizedBox(
          height: 34,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: AppMotion.enterDuration,
                  curve: AppMotion.enter,
                  left: selectedIndex * segmentWidth + 2,
                  top: 2,
                  bottom: 2,
                  width: segmentWidth - 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.brass.withValues(alpha: 0.25),
                      border: Border.all(color: AppColors.brass.withValues(alpha: 0.6), width: 0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final (i, label) in labels.indexed)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => onChanged(i),
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: Text(
                              label,
                              style: i == selectedIndex
                                  ? AppTextStyles.captionStrong
                                  : AppTextStyles.captionStrong.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary.withValues(alpha: 0.6),
                                    ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
