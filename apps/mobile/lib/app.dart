import "package:flutter/material.dart";
import "features/agenda/agenda_screen.dart";
import "features/home/home_screen.dart";
import "features/valorant_season/valorant_season_screen.dart";
import "theme/tokens.dart";
import "widgets/glass_tab_bar.dart";

const _items = [
  GlassTabBarItem(icon: Icons.wb_sunny_rounded, label: "Aujourd'hui"),
  GlassTabBarItem(icon: Icons.calendar_today_rounded, label: "Agenda"),
  GlassTabBarItem(icon: Icons.star_rounded, label: "Suivis"),
  GlassTabBarItem(icon: Icons.casino_rounded, label: "Jeu"),
];

/// Tab bar V2 : Aujourd'hui · Agenda · Suivis · Jeu (`docs/02`). Suivis et
/// Jeu restent en placeholder au J3 (`docs/04`) : pas de compte/abonnements
/// avant le J4.
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
          _FollowsPlaceholder(),
          _ComingSoon(label: "Jeu du jour"),
        ],
      ),
      bottomNavigationBar: GlassTabBar(items: _items, currentIndex: _index, onTap: (i) => setState(() => _index = i)),
    );
  }
}

class _FollowsPlaceholder extends StatelessWidget {
  const _FollowsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Suivis", style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              "Les comptes et abonnements arrivent au prochain jalon. En attendant, voici ce que tu peux déjà suivre :",
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.sports_esports_rounded),
                title: const Text("Valorant"),
                subtitle: const Text("Saison VCT 2026"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ValorantSeasonScreen())),
              ),
            ),
          ],
        ),
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
