import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "core/navigation.dart";
import "features/agenda/agenda_screen.dart";
import "features/competitions/competitions_screen.dart";
import "features/follows/follows_screen.dart";
import "features/home/home_screen.dart";
import "theme/tokens.dart";
import "widgets/glass_tab_bar.dart";

// Icônes fines (trait), pas les variantes "_rounded" pleines : la maquette
// dessine des icônes en contour (`docs/maquettes/svg/17-accueil.svg`).
const _items = [
  GlassTabBarItem(icon: Icons.wb_sunny_outlined, label: "Aujourd'hui"),
  GlassTabBarItem(icon: Icons.calendar_today_outlined, label: "Agenda"),
  GlassTabBarItem(icon: Icons.explore_outlined, label: "Compétitions", featured: true),
  GlassTabBarItem(icon: Icons.star_outline_rounded, label: "Suivis"),
  GlassTabBarItem(icon: Icons.casino_outlined, label: "Jeu"),
];

/// Tab bar V2 : Aujourd'hui · Agenda · Compétitions · Suivis · Jeu (`docs/02`). Suivis est
/// connecté aux abonnements depuis le J4 (`docs/04`) ; Jeu reste en
/// placeholder (hors périmètre).
class NewsApp extends ConsumerWidget {
  const NewsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: index,
        children: const [
          HomeScreen(),
          AgendaScreen(),
          CompetitionsScreen(),
          FollowsScreen(),
          _ComingSoon(label: "Jeu du jour"),
        ],
      ),
      bottomNavigationBar: GlassTabBar(items: _items, currentIndex: index, onTap: ref.read(tabIndexProvider.notifier).select),
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
