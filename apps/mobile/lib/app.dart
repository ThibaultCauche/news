import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "core/auto_refresh.dart";
import "core/navigation.dart";
import "features/agenda/agenda_screen.dart";
import "features/competitions/competitions_screen.dart";
import "features/discussion/discussion_screen.dart";
import "features/forum/forum_providers.dart";
import "features/home/home_screen.dart";
import "features/games/games_screen.dart";
import "theme/tokens.dart";
import "widgets/glass_tab_bar.dart";
import "widgets/offline_banner.dart";
import "widgets/update_gate.dart";

// Icônes fines (trait), pas les variantes "_rounded" pleines : la maquette
// dessine des icônes en contour (`docs/maquettes/svg/17-accueil.svg`).
List<GlassTabBarItem> _items(int unread) => [
  const GlassTabBarItem(icon: Icons.wb_sunny_outlined, label: "Aujourd'hui"),
  const GlassTabBarItem(icon: Icons.calendar_today_outlined, label: "Agenda"),
  const GlassTabBarItem(icon: Icons.explore_outlined, label: "Compétitions", featured: true),
  GlassTabBarItem(icon: Icons.chat_bubble_outline_rounded, label: "Discussion", badge: unread),
  const GlassTabBarItem(icon: Icons.casino_outlined, label: "Jeux"),
];

/// Tab bar : Aujourd'hui · Agenda · Compétitions · Discussion · Jeux (`docs/02`). L'onglet Suivis a
/// disparu au J11 : son contenu est revenu sur l'Accueil (« Tes suivis »), le profil s'ouvre
/// depuis l'avatar de l'Accueil. Le 4ᵉ onglet est la Discussion depuis le J24 (groupes, messages
/// privés, discussions suivies, pastille de non-lus). Jeux ouvre les jeux de l'appli (pronostics
/// pour l'instant).
class NewsApp extends ConsumerWidget {
  const NewsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    final unread = ref.watch(unreadCountProvider);
    return AutoRefresh(
      // Au-dessus de tout, tab bar comprise : l'écran de mise à jour obligatoire ne laisse rien d'accessible (J21).
      child: Stack(fit: StackFit.expand, children: [
      Scaffold(
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
              DiscussionScreen(),
              GamesScreen(),
            ],
          ),
          // Au-dessus de la tab bar flottante.
          const Positioned(left: AppSpacing.md, right: AppSpacing.md, bottom: 104, child: Center(child: OfflineBanner())),
        ],
      ),
      bottomNavigationBar: GlassTabBar(items: _items(unread), currentIndex: index, onTap: ref.read(tabIndexProvider.notifier).select),
    ),
      const UpdateGate(),
      ]),
    );
  }
}
