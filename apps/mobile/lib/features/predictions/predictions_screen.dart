import "../../theme/app_theme.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/auth/account.dart";
import "../../core/clock.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/event_card.dart";
import "../../widgets/page_title.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../account/auth_screen.dart";
import "../agenda/agenda_screen.dart";
import "../competitions/competitions_data.dart";
import "../learn/learn_screen.dart";
import "../next_match/next_match_screen.dart";
import "../profile/community_providers.dart";
import "../profile/groups_screen.dart";

/// Jeu « Pronostics » (docs/04 J11), ouvert depuis l'onglet Jeux : tes groupes d'amis (tous jeux
/// confondus) puis les matchs à pronostiquer dans les 7 prochains jours, filtrables par jeu ou
/// sport (les jeux du catalogue : Valorant aujourd'hui, d'autres ensuite). Optionnel : l'invité y
/// trouve l'invitation à créer un compte.
class PredictionsScreen extends ConsumerWidget {
  const PredictionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(signedInProvider);
    return Scaffold(
      appBar: AppBar(actions: const [LearnHelpButton(articleId: "pronostics", game: "app")]),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(predictionsProvider);
            ref.invalidate(groupsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const PageTitle("Pronostics"),
              const SizedBox(height: AppSpacing.xs),
              const Text("Devine les résultats en points fictifs et compare-toi à tes amis.", style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.lg),
              if (!signedIn) const _GuestCard() else ...const [GroupsSection(), SizedBox(height: AppSpacing.lg), _UpcomingSection()],
              const SizedBox(height: AppSpacing.xl * 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Un compte est nécessaire", style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          const Text("Crée un compte pour pronostiquer les matchs et jouer avec tes amis.", style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen())),
            child: const Text("Créer un compte"),
          ),
        ],
      ),
    );
  }
}

/// Tous les jeux et sports du catalogue, à plat (une puce chacun).
List<CatalogGameDto> catalogGames(CatalogDto? catalog) => [for (final category in catalog?.categories ?? const <CatalogCategoryDto>[]) ...category.games];

/// Matchs à venir sur 7 jours (deux équipes connues) : un appui ouvre le match, où se pose le pronostic.
class _UpcomingSection extends ConsumerStatefulWidget {
  const _UpcomingSection();

  @override
  ConsumerState<_UpcomingSection> createState() => _UpcomingSectionState();
}

class _UpcomingSectionState extends ConsumerState<_UpcomingSection> {
  // `null` = tous les jeux.
  String? _game;

  @override
  Widget build(BuildContext context) {
    final games = catalogGames(ref.watch(catalogProvider).value);
    final selected = games.where((g) => g.slug == _game).firstOrNull;
    final today = ref.watch(todayProvider);
    final query = (
      from: DateTime(today.year, today.month, today.day),
      to: DateTime(today.year, today.month, today.day + 7),
      category: null,
      leagueIds: selected?.leagues.map((l) => l.id).join(","),
      mine: false,
    );
    final agenda = ref.watch(agendaProvider(query));
    final predictions = ref.watch(predictionsProvider).value ?? const <String, PredictionDto>{};
    final scoresHidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    final events = (agenda.value?.events.toList() ?? const <EventSummaryDto>[]).where((e) => e.status == "scheduled" && e.participants.length == 2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("MATCHS À PRONOSTIQUER"),
        const SizedBox(height: AppSpacing.sm),
        if (games.length > 1)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ChoiceChip(label: const Text("Tous"), selected: _game == null, onSelected: (_) => setState(() => _game = null)),
                for (final game in games) ...[
                  const SizedBox(width: AppSpacing.sm),
                  ChoiceChip(label: Text(game.name), selected: _game == game.slug, onSelected: (_) => setState(() => _game = game.slug)),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        if (!agenda.hasValue && !agenda.hasError) const SkeletonCards(count: 3, height: 84, padding: EdgeInsets.zero),
        if (agenda.hasError && !agenda.hasValue) ErrorState(message: "Impossible de charger les matchs.", compact: true, onRetry: () => ref.invalidate(agendaProvider(query))),
        if (agenda.hasValue && events.isEmpty) const Text("Aucun match à venir cette semaine.", style: TextStyle(color: AppColors.textSecondary)),
        for (final event in events) ...[
          EventCard(
            event: event,
            scoresHidden: scoresHidden,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
            footer: _PickLine(event: event, prediction: predictions[event.id]),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _PickLine extends StatelessWidget {
  const _PickLine({required this.event, required this.prediction});

  final EventSummaryDto event;
  final PredictionDto? prediction;

  @override
  Widget build(BuildContext context) {
    final picked = prediction == null ? null : event.participants.where((p) => p.entityId == prediction!.pickedEntityId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
      child: Text(
        picked == null ? "Pas encore de pronostic" : "Ton pronostic : ${picked.shortName ?? picked.name}",
        style: TextStyle(color: picked == null ? AppColors.textTertiary : AppColors.gold, fontSize: AppTypography.caption, fontWeight: FontWeight.w600),
      ),
    );
  }
}
