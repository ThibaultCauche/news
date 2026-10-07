import "../../theme/app_theme.dart";
import "package:dio/dio.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/games.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/follow_button.dart";
import "../../widgets/page_subtitle.dart";
import "../../widgets/page_title.dart";
import "../../widgets/section_card.dart";
import "../../widgets/stream_language_picker.dart";
import "../follows/follows_provider.dart";
import "../learn/learn_screen.dart";

// Éditorial, écrit à la main comme le glossaire (`docs/03` §7) : pas une règle
// calculée, une suggestion pour démarrer. Champions 2026 réunit les trois
// (`docs/01` — groupes tirés au sort), donc toujours trouvables via
// `GET /v1/entities/by-short-name/:shortName`.
const _suggestedTeams = [
  (game: "valorant", shortName: "G2", reason: "Favori de Champions cette année : idéal pour vivre la phase finale."),
  (game: "valorant", shortName: "KC", reason: "L'équipe française la plus suivie, avec la plus grosse ambiance."),
  (game: "valorant", shortName: "PR", reason: "Le style le plus offensif du circuit, des matchs très spectaculaires."),
  (game: "league-of-legends", shortName: "T1", reason: "L'équipe la plus titrée aux Worlds, portée par Faker, le joueur le plus connu."),
  (game: "league-of-legends", shortName: "G2", reason: "Le grand nom de l'Europe : des matchs spectaculaires, et un public très présent."),
  (game: "league-of-legends", shortName: "KC", reason: "L'équipe française la plus suivie, avec la plus grosse ambiance."),
];

/// Les jeux que couvre l'appli (J23, #I8) et ceux qui arrivent : le choix de l'onboarding. Un jeu « bientôt » n'est pas
/// sélectionnable.
const onboardingGames = [("valorant", "Valorant"), ("league-of-legends", "League of Legends")];
const _soonGames = ["Counter-Strike 2", "Rocket League"];

/// Jeux cochés à l'onboarding : les suggestions d'équipes et l'aide « Je ne connais pas… » suivent ce choix.
class OnboardingGamesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {onboardingGames.first.$1};

  /// Au moins un jeu reste coché : on ne peut pas décocher le dernier.
  void toggle(String slug) {
    if (state.contains(slug)) {
      if (state.length > 1) state = {...state}..remove(slug);
    } else {
      state = {...state, slug};
    }
  }
}

final onboardingGamesProvider = NotifierProvider<OnboardingGamesNotifier, Set<String>>(OnboardingGamesNotifier.new);

final suggestedTeamsProvider = FutureProvider.autoDispose<List<(EntityResponseDto, String)>>((ref) async {
  final api = ref.watch(apiClientProvider).getEntitiesApi();
  final games = ref.watch(onboardingGamesProvider);
  // En parallèle (J18) : trois requêtes l'une après l'autre attendaient trois délais en cas de panne.
  final results = await Future.wait([
    for (final team in _suggestedTeams.where((t) => games.contains(t.game)))
      () async {
        try {
          final data = (await api.entitiesControllerGetByShortName(shortName: team.shortName, game: team.game)).data;
          return data == null ? null : (data, team.reason);
        } on DioException catch (e) {
          // Équipe pas encore ingérée dans cet environnement (404) : on l'ignore plutôt que de casser
          // l'onboarding. Toute autre erreur (réseau, serveur) remonte pour afficher « Réessayer »
          // au lieu d'un faux « Aucune suggestion ».
          if (e.response?.statusCode != 404) rethrow;
          return null;
        }
      }(),
  ]);
  return [for (final r in results) ?r];
});

/// Onboarding (écrans 11-12, `docs/02`) : montré une fois au premier lancement
/// (`AuthStore.hasSeenOnboarding`). "Passer" a le même effet que d'aller au
/// bout : aucune des deux pages ne bloque l'accès à l'appli.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: widget.onDone, child: const Text("Passer"))],
      ),
      body: switch (_page) {
        0 => _SubjectsPage(onContinue: () => setState(() => _page = 1)),
        1 => _LanguagePage(onContinue: () => setState(() => _page = 2)),
        _ => _TeamsPage(onDone: widget.onDone),
      },
    );
  }
}

class _SubjectsPage extends ConsumerWidget {
  const _SubjectsPage({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(onboardingGamesProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Le contenu défile (quatre sujets et la liste des jeux dépassent un petit écran), les boutons restent en bas.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          Row(
            children: [
              SvgPicture.asset("assets/ornaments/monogram.svg", width: 40, height: 40),
              const SizedBox(width: AppSpacing.sm),
              Text("KERYX", style: AppTextStyles.sectionTitle.copyWith(letterSpacing: 4)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const PageTitle("Qu'est-ce qui t'intéresse ?"),
          const SizedBox(height: AppSpacing.xs),
          const PageSubtitle("Choisis au moins un sujet. Tu pourras changer plus tard."),
          const SizedBox(height: AppSpacing.lg),
          _CategoryTile(label: "E-sport", caption: games.length > 1 ? "${games.length} jeux choisis" : "1 jeu choisi", selected: true),
          const SizedBox(height: AppSpacing.sm),
          const _CategoryTile(label: "Sport", caption: "Bientôt", selected: false),
          const SizedBox(height: AppSpacing.sm),
          const _CategoryTile(label: "Politique", caption: "Bientôt", selected: false),
          const SizedBox(height: AppSpacing.sm),
          const _CategoryTile(label: "Streams", caption: "Bientôt", selected: false),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("QUELS JEUX ?", style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.label)),
                const SizedBox(height: AppSpacing.sm),
                for (final (slug, name) in onboardingGames)
                  _GameRow(label: name, selected: games.contains(slug), onTap: () => ref.read(onboardingGamesProvider.notifier).toggle(slug)),
                for (final name in _soonGames) _GameRow(label: name, selected: false),
              ],
            ),
          ),
                ],
              ),
            ),
          ),
          // Une aide par jeu coché : « Je ne connais pas Valorant », « Je ne connais pas League of Legends ».
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                for (final (slug, name) in onboardingGames)
                  if (games.contains(slug))
                    TextButton.icon(
                      onPressed: () => openLearnArticle(context, game: slug, articleId: "le-jeu"),
                      icon: const Icon(Icons.help_rounded, size: 18, color: AppColors.gold),
                      label: Text("Je ne connais pas $name"),
                    ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onContinue, child: const Padding(padding: EdgeInsets.all(AppSpacing.sm), child: Text("Continuer"))),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label, required this.caption, required this.selected});

  final String label;
  final String caption;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: selected ? 1 : 0.5,
      child: SectionCard(
        child: Row(
          children: [
            if (selected) ...[const Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 20), const SizedBox(width: AppSpacing.sm)],
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(caption, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
          ],
        ),
      ),
    );
  }
}

/// Un jeu de la liste : cochable (`onTap`), ou grisé « bientôt » quand il n'est pas encore couvert.
class _GameRow extends StatelessWidget {
  const _GameRow({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Opacity(
          opacity: onTap == null ? 0.4 : (selected ? 1 : 0.7),
          child: Row(
            children: [
              Icon(selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 20, color: selected ? AppColors.gold : AppColors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label)),
              if (onTap == null) const Text("Bientôt", style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
            ],
          ),
        ),
      ),
    );
  }
}

/// La langue des streams (J21) : celle du téléphone est déjà choisie, on demande seulement de confirmer.
class _LanguagePage extends StatelessWidget {
  const _LanguagePage({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle("Tu regardes en quelle langue ?"),
          const SizedBox(height: AppSpacing.xs),
          const PageSubtitle("Pour chaque match, on met en premier la diffusion dans ta langue. Modifiable dans les Réglages."),
          const SizedBox(height: AppSpacing.lg),
          const Expanded(child: SingleChildScrollView(child: StreamLanguagePicker())),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onContinue, child: const Padding(padding: EdgeInsets.all(AppSpacing.sm), child: Text("Continuer"))),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _TeamsPage extends ConsumerWidget {
  const _TeamsPage({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(suggestedTeamsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle("Des équipes pour commencer"),
          const SizedBox(height: AppSpacing.xs),
          const PageSubtitle("Choisies pour débuter, chacune pour une bonne raison."),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: switch (teams) {
              AsyncData(:final value) => value.isEmpty
                  ? const Center(child: Text("Aucune suggestion pour l'instant.", style: TextStyle(color: AppColors.textSecondary)))
                  : ListView.separated(
                      itemCount: value.length,
                      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) => _TeamSuggestionCard(entity: value[i].$1, reason: value[i].$2),
                    ),
              AsyncError() => ErrorState(message: "Impossible de charger les suggestions.", onRetry: () => ref.invalidate(suggestedTeamsProvider)),
              _ => const SkeletonCards(count: 3, height: 100, padding: EdgeInsets.zero),
            },
          ),
          const Text("Tu seras prévenu avant chaque match. Modifiable à tout moment.", style: TextStyle(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onDone, child: const Padding(padding: EdgeInsets.all(AppSpacing.sm), child: Text("C'est parti"))),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _TeamSuggestionCard extends ConsumerWidget {
  const _TeamSuggestionCard({required this.entity, required this.reason});

  final EntityResponseDto entity;
  final String reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = isFollowing(ref.watch(followsProvider).value, FollowTargetType.entity, entity.id);
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.background,
            child: Text((entity.shortName ?? entity.name).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entity.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                // Le jeu départage « G2 » de Valorant et « G2 » de League of Legends ; sous le nom, pour ne pas l'écraser.
                Text(
                  [gameLabel(entity.game), entity.region].whereType<String>().where((t) => t.isNotEmpty).join(" · "),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text("Pourquoi", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label)),
                Text(reason, style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FollowButton(
            following: following,
            onPressed: () => runOrShowError(
              context,
              () => following
                  ? ref.read(followsControllerProvider).unfollow(FollowTargetType.entity, entity.id)
                  : ref.read(followsControllerProvider).follow(FollowTargetType.entity, entity.id),
            ),
          ),
        ],
      ),
    );
  }
}
