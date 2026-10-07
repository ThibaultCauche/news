import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/game_logo.dart";
import "../../widgets/live_dot.dart";
import "competitions_data.dart";
import "game_screen.dart";

typedef _Entry = ({CatalogChildDto serie, CatalogLeagueDto league, DateTime? start, DateTime? end});

/// Onglet « Compétitions » d'un jeu sans frise de saison (League of Legends, J23) : ses séries en cours, à venir
/// et récentes, tirées du catalogue déjà chargé. Valorant garde sa frise (`valorantSeasonProvider`), qui suppose
/// une ligue unique découpée en étapes ; League of Legends a plusieurs ligues régionales et des tournois
/// internationaux (MSI, Worlds) qui ne forment pas une seule saison.
class GameCompetitionsTab extends ConsumerWidget {
  const GameCompetitionsTab({super.key, required this.game, this.now});

  final CatalogGameDto game;
  /// Pour les tests ; `DateTime.now()` sinon.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = this.now ?? DateTime.now();
    // Le champion dit qui a gagné : masqué en sans spoil.
    final showChampion = !(ref.watch(userSettingProvider).value?.spoilerFree ?? true);
    final live = <_Entry>[];
    final upcoming = <_Entry>[];
    final recent = <_Entry>[];
    for (final league in game.leagues) {
      for (final serie in league.children) {
        final entry = (serie: serie, league: league, start: _parse(serie.startsAt), end: _parse(serie.endsAt));
        if (serie.live) {
          live.add(entry);
        } else if (entry.start != null && entry.start!.isAfter(now)) {
          upcoming.add(entry);
        } else if (serie.major && entry.end != null && entry.end!.isBefore(now)) {
          recent.add(entry);
        }
      }
    }
    // Les grands rendez-vous d'abord, puis par date ; les terminées de la plus récente à la plus ancienne.
    int byMajorThenDate(_Entry a, _Entry b) {
      if (a.serie.major != b.serie.major) return a.serie.major ? -1 : 1;
      return (a.start ?? DateTime(2100)).compareTo(b.start ?? DateTime(2100));
    }

    live.sort(byMajorThenDate);
    upcoming.sort((a, b) => a.start!.compareTo(b.start!));
    recent.sort((a, b) => b.end!.compareTo(a.end!));
    if (live.isEmpty && upcoming.isEmpty && recent.isEmpty) {
      return Center(child: Text("Aucune compétition ${game.name} pour l'instant.", style: const TextStyle(color: AppColors.textSecondary)));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        _Section(title: "EN COURS", entries: live, isLive: true),
        _Section(title: "À VENIR", entries: upcoming.take(8).toList()),
        _Section(title: "TERMINÉES RÉCEMMENT", entries: recent.take(5).toList(), showChampion: showChampion),
      ],
    );
  }
}

DateTime? _parse(String? iso) => iso == null ? null : DateTime.parse(iso).toLocal();

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.entries, this.isLive = false, this.showChampion = false});

  final String title;
  final List<_Entry> entries;
  final bool isLive;
  final bool showChampion;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            if (isLive) ...[const LiveDot(), const SizedBox(width: AppSpacing.sm)],
            Text(title, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: isLive ? AppColors.live : null)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final e in entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: LeagueLogo(imageUrl: e.league.imageUrl, size: 44),
            title: Text(e.serie.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              [
                e.league.name,
                formatDateRange(e.serie.startsAt, e.serie.endsAt),
                if (showChampion && e.serie.champion != null) "Champion : ${e.serie.champion!.shortName ?? e.serie.champion!.name}",
              ].whereType<String>().join(" · "),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            onTap: () => openCompetitionPage(context, id: e.serie.id, name: e.serie.name),
          ),
      ],
    );
  }
}
