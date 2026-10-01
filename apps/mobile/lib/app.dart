import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "core/auto_refresh.dart";
import "core/navigation.dart";
import "features/agenda/agenda_screen.dart";
import "features/competitions/competitions_screen.dart";
import "features/home/home_screen.dart";
import "features/games/games_screen.dart";
import "theme/tokens.dart";
import "widgets/glass_tab_bar.dart";

// Icônes fines (trait), pas les variantes "_rounded" pleines : la maquette
// dessine des icônes en contour (`docs/maquettes/svg/17-accueil.svg`).
const _items = [
  GlassTabBarItem(icon: Icons.wb_sunny_outlined, label: "Aujourd'hui"),
  GlassTabBarItem(icon: Icons.calendar_today_outlined, label: "Agenda"),
  GlassTabBarItem(icon: Icons.explore_outlined, label: "Compétitions", featured: true),
  GlassTabBarItem(icon: Icons.hourglass_empty_rounded, label: "Bientôt"),
  GlassTabBarItem(icon: Icons.casino_outlined, label: "Jeux"),
];

/// Tab bar : Aujourd'hui · Agenda · Compétitions · (vide) · Jeux (`docs/02`). L'onglet Suivis a
/// disparu au J11 : son contenu est revenu sur l'Accueil (« Tes suivis »), le profil s'ouvre
/// depuis l'avatar de l'Accueil, et le 4ᵉ onglet reste vide en attendant un usage. Jeux ouvre les
/// jeux de l'appli (pronostics pour l'instant).
class NewsApp extends ConsumerWidget {
  const NewsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    return AutoRefresh(
      child: Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // Lueur laiton en haut de chaque onglet (J16), statique.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.brass.withValues(alpha: 0.12), Colors.transparent]),
                ),
              ),
            ),
          ),
          IndexedStack(
            index: index,
            children: const [
              HomeScreen(),
              AgendaScreen(),
              CompetitionsScreen(),
              _ComingSoon(label: "Cet onglet"),
              GamesScreen(),
            ],
          ),
        ],
      ),
      bottomNavigationBar: GlassTabBar(items: _items, currentIndex: index, onTap: ref.read(tabIndexProvider.notifier).select),
    ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Text("$label — bientôt disponible", style: const TextStyle(color: AppColors.textSecondary)),
      ),
    );
  }
}
