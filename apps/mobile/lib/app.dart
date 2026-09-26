import "package:flutter/material.dart";
import "features/agenda/agenda_screen.dart";
import "features/follows/follows_screen.dart";
import "features/home/home_screen.dart";
import "theme/tokens.dart";
import "widgets/glass_tab_bar.dart";

const _items = [
  GlassTabBarItem(icon: Icons.wb_sunny_rounded, label: "Aujourd'hui"),
  GlassTabBarItem(icon: Icons.calendar_today_rounded, label: "Agenda"),
  GlassTabBarItem(icon: Icons.star_rounded, label: "Suivis"),
  GlassTabBarItem(icon: Icons.casino_rounded, label: "Jeu"),
];

/// Tab bar V2 : Aujourd'hui · Agenda · Suivis · Jeu (`docs/02`). Suivis est
/// connecté aux abonnements depuis le J4 (`docs/04`) ; Jeu reste en
/// placeholder (hors périmètre).
class NewsApp extends StatefulWidget {
  const NewsApp({super.key});

  @override
  State<NewsApp> createState() => _NewsAppState();
}

class _NewsAppState extends State<NewsApp> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          AgendaScreen(),
          FollowsScreen(),
          _ComingSoon(label: "Jeu du jour"),
        ],
      ),
      bottomNavigationBar: GlassTabBar(items: _items, currentIndex: _index, onTap: (i) => setState(() => _index = i)),
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
