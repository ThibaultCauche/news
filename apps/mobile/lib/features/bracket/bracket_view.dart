import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";
import "../../theme/tokens.dart";

/// Deux façons de lire le même tableau (J20) : la pyramide (les équipes qui montent vers la
/// finale, de gauche à droite) ou le cercle (le tableau enroulé autour de la finale).
enum BracketView { pyramid, circle }

/// Le choix est retenu sur le téléphone et vaut pour les poules comme pour la phase finale :
/// la même personne ne devrait pas lire deux dessins différents d'une page à l'autre.
class BracketViewNotifier extends Notifier<BracketView> {
  static const _key = "bracket.view";

  @override
  BracketView build() {
    _load();
    return BracketView.pyramid;
  }

  // Sans plugin (tests), on garde la pyramide : un échec de lecture ne doit rien casser.
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_key) == BracketView.circle.name) state = BracketView.circle;
    } catch (_) {}
  }

  void select(BracketView view) {
    state = view;
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_key, view.name)).catchError((_) => false);
  }
}

final bracketViewProvider = NotifierProvider<BracketViewNotifier, BracketView>(BracketViewNotifier.new);

/// Deux petits ronds avec une icône (pyramide, cercle) dans la ligne du titre : pas de ligne en plus.
class BracketViewToggle extends ConsumerWidget {
  const BracketViewToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(bracketViewProvider);
    return Transform.translate(
      offset: const Offset(6, 0),
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundButton(icon: Icons.change_history_rounded, tooltip: "Pyramide", selected: view == BracketView.pyramid, onTap: () => ref.read(bracketViewProvider.notifier).select(BracketView.pyramid)),
        const SizedBox(width: AppSpacing.sm),
        _RoundButton(icon: Icons.trip_origin_rounded, tooltip: "Cercle", selected: view == BracketView.circle, onTap: () => ref.read(bracketViewProvider.notifier).select(BracketView.circle)),
      ],
    ));
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.selected, required this.onTap});

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // 44 px de zone d'appui autour d'un rond de 32.
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.brass : AppColors.surface,
                border: Border.all(color: selected ? AppColors.brass : AppColors.surfaceBorderHighlight),
              ),
              child: Icon(icon, size: 17, color: selected ? AppColors.background : AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
