import "package:flutter/material.dart";

import "../../theme/tokens.dart";

/// Illustrations des tutos, dessinées avec des widgets et des icônes du thème :
/// aucune image tierce (droits), et elles suivent les tokens (règle 12). Les
/// couleurs sémantiques gardent leur sens (or = « mon équipe », vert = victoire) ;
/// les dégradés d'`AppGradients` donnent de la couleur sans rien signifier.
const learnIcons = <String, IconData>{
  "game": Icons.sports_esports_rounded,
  "round": Icons.timer_rounded,
  "roles": Icons.groups_rounded,
  "map": Icons.map_rounded,
  "watch": Icons.live_tv_rounded,
  "place": Icons.place_rounded,
  "person": Icons.person_rounded,
  "person_off": Icons.person_off_rounded,
  "build": Icons.build_rounded,
  "timer": Icons.timer_rounded,
  "timer_off": Icons.timer_off_rounded,
  "flag": Icons.flag_rounded,
  "swap": Icons.swap_horiz_rounded,
  "emoji": Icons.emoji_events_rounded,
  "equal": Icons.drag_handle_rounded,
  "plus2": Icons.exposure_plus_2_rounded,
  "shopping": Icons.shopping_bag_rounded,
  "target": Icons.my_location_rounded,
  "savings": Icons.savings_rounded,
  "bolt": Icons.bolt_rounded,
  "cloud": Icons.cloud_rounded,
  "flash": Icons.flash_on_rounded,
  "heal": Icons.healing_rounded,
  "sensors": Icons.sensors_rounded,
  "star": Icons.star_rounded,
  "visibility": Icons.visibility_rounded,
  "shield": Icons.shield_rounded,
  "block": Icons.block_rounded,
  "check": Icons.check_circle_rounded,
  "arrow_down": Icons.south_rounded,
  "replay": Icons.replay_rounded,
  "close": Icons.close_rounded,
};

/// Bandeau en haut d'un article : dégradé + grande icône.
class LearnHero extends StatelessWidget {
  const LearnHero({super.key, required this.icon, required this.gradient, required this.child});

  final IconData icon;
  final int gradient;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppGradients.highlights[gradient % AppGradients.highlights.length];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.surfaceBorderHighlight),
      ),
      child: Stack(
        children: [
          Positioned(right: -14, top: -14, child: Icon(icon, size: 120, color: Colors.white.withValues(alpha: 0.06))),
          Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
        ],
      ),
    );
  }
}

/// Pastille d'icône des cartes de la liste.
class LearnIconTile extends StatelessWidget {
  const LearnIconTile({super.key, required this.icon, required this.gradient});

  final IconData icon;
  final int gradient;

  @override
  Widget build(BuildContext context) {
    final colors = AppGradients.highlights[gradient % AppGradients.highlights.length];
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: Border.all(color: AppColors.surfaceBorderHighlight),
      ),
      child: Icon(icon, color: AppColors.textPrimary),
    );
  }
}

/// Schéma d'un article ou d'une section : un nom (`duel`, `map`, `bo3`) ou un
/// objet `{type: chips | flow | stats, items: [...]}`, donc un nouveau jeu se
/// décrit entièrement dans son JSON.
class LearnVisual extends StatelessWidget {
  const LearnVisual({super.key, required this.spec});

  final Object spec;

  @override
  Widget build(BuildContext context) {
    final spec = this.spec;
    if (spec is String) {
      return switch (spec) {
        "duel" => const _DuelVisual(),
        "map" => const _MapVisual(),
        "bo3" => const Bo3Example(),
        _ => const SizedBox.shrink(),
      };
    }
    final items = ((spec as Map)["items"] as List).cast<Map<String, dynamic>>();
    return switch (spec["type"]) {
      "chips" => _Chips(items),
      "flow" => _Flow(items),
      "stats" => _Stats(items),
      _ => const SizedBox.shrink(),
    };
  }
}

IconData _icon(String? name) => learnIcons[name] ?? Icons.circle_outlined;

class _Team extends StatelessWidget {
  const _Team(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: 2,
        children: [for (var i = 0; i < 5; i++) Icon(icon, size: 22, color: AppColors.textPrimary)],
      ),
    ],
  );
}

class _DuelVisual extends StatelessWidget {
  const _DuelVisual();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const Flexible(child: _Team("ATTAQUE", Icons.person_rounded)),
          Text("VS", style: Theme.of(context).textTheme.labelSmall),
          const Flexible(child: _Team("DÉFENSE", Icons.person_outline_rounded)),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(color: AppColors.surfaceHighlight, borderRadius: BorderRadius.circular(AppRadii.pill)),
        child: const Text("Premier à 13 rounds", style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    ],
  );
}

/// Étapes à la suite : icône + libellé, séparés par des chevrons.
class _Flow extends StatelessWidget {
  const _Flow(this.items);

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (i, item) in items.indexed) ...[
        Expanded(
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: AppColors.surfaceHighlight, shape: BoxShape.circle),
                child: Icon(_icon(item["icon"] as String?), color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                item["label"] as String,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.caption),
              ),
            ],
          ),
        ),
        if (i < items.length - 1)
          const Padding(padding: EdgeInsets.only(top: 12), child: Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary)),
      ],
    ],
  );
}

/// Tuiles à deux colonnes : icône, titre, précision. Une rangée = même hauteur
/// pour les deux tuiles (`IntrinsicHeight`), et une case vide complète une
/// dernière rangée impaire pour que toutes gardent la même largeur.
class _Chips extends StatelessWidget {
  const _Chips(this.items);

  final List<Map<String, dynamic>> items;

  Widget _tile(Map<String, dynamic> item) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm + 2),
    decoration: BoxDecoration(color: AppColors.surfaceHighlight, borderRadius: BorderRadius.circular(AppRadii.chip)),
    child: Row(
      children: [
        Icon(_icon(item["icon"] as String?), color: AppColors.textPrimary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(item["title"] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(item["sub"] as String, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.label)),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < items.length; i += 2) ...[
        if (i > 0) const SizedBox(height: AppSpacing.cardGap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _tile(items[i])),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(child: i + 1 < items.length ? _tile(items[i + 1]) : const SizedBox.shrink()),
            ],
          ),
        ),
      ],
    ],
  );
}

/// Gros chiffres côte à côte (ex. score de série et score de carte).
class _Stats extends StatelessWidget {
  const _Stats(this.items);

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, item) in items.indexed) ...[
        if (i > 0) const SizedBox(width: AppSpacing.cardGap),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: AppColors.surfaceHighlight, borderRadius: BorderRadius.circular(AppRadii.chip)),
            child: Column(
              children: [
                Text(item["big"] as String, style: const TextStyle(fontSize: AppTypography.heroScore, fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item["sub"] as String,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.label),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

class _MapVisual extends StatelessWidget {
  const _MapVisual();

  Widget _site(String letter) => Expanded(
    child: Container(
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: Border.all(color: AppColors.surfaceBorderHighlight),
      ),
      child: Text(letter, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(children: [_site("A"), const SizedBox(width: AppSpacing.cardGap), _site("B")]),
      const SizedBox(height: AppSpacing.sm),
      const Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.textSecondary),
      Text("Départ des attaquants", style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

/// Exemple en 3 cartes d'un BO3 (écran 04 de `docs/maquettes`) : or = l'équipe A,
/// comme « ton équipe » ailleurs. Partagé par la feuille glossaire et le tuto.
class Bo3Example extends StatelessWidget {
  const Bo3Example({super.key});

  @override
  Widget build(BuildContext context) {
    const winners = ["A", "B", "A"];
    return Row(
      children: [
        for (final (i, w) in winners.indexed) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              decoration: BoxDecoration(
                color: w == "A" ? AppColors.gold.withValues(alpha: 0.16) : AppColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(AppRadii.chip),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Carte ${i + 1}", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.label)),
                  const SizedBox(height: 2),
                  Text(
                    "$w gagne",
                    style: TextStyle(fontWeight: FontWeight.w700, color: w == "A" ? AppColors.gold : AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
