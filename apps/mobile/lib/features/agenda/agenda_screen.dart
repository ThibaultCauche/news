import "package:flutter/material.dart";
import "package:flutter/rendering.dart" show ScrollCacheExtent;
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/clock.dart";
import "../../core/date_x.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/event_card.dart";
import "../next_match/next_match_screen.dart";

typedef AgendaQuery = ({DateTime from, DateTime to, String? category, String? leagueIds});

final agendaProvider = FutureProvider.autoDispose.family<AgendaResponseDto, AgendaQuery>((ref, query) async {
  final response = await ref.watch(apiClientProvider).getAgendaApi().agendaControllerGetAgenda(
    from: query.from.toUtc().toIso8601String(),
    to: query.to.toUtc().toIso8601String(),
    category: query.category,
    leagueIds: query.leagueIds,
  );
  return response.data!;
});

/// Ligues racines d'une catégorie (un jeu = une ligue racine, ex. "VCT" pour
/// Valorant) : liste à cocher du filtre "E-sport" (`GET /v1/competitions/roots`).
final competitionRootsProvider = FutureProvider.autoDispose.family<List<CompetitionRootDto>, String>((ref, category) async {
  final response = await ref.watch(apiClientProvider).getCompetitionsApi().competitionsControllerGetRoots(category: category);
  return response.data!.toList();
});

const _categories = [(label: "Tout", slug: null), (label: "E-sport", slug: "esport"), (label: "Sport", slug: "sport"), (label: "Politique", slug: "politique")];

/// Écran 09 (`docs/02`). L'export `.ics` de la maquette n'est pas prévu au
/// périmètre du J3 (`docs/04`) : le bouton reste visible mais désactivé.
///
/// Avec `leagueIds` (onglet Agenda d'une page jeu, J9), l'écran est intégré :
/// filtre fixé sur ces ligues, sans titre ni pastilles de catégorie, et sans
/// toucher au filtre mémorisé de l'onglet principal.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key, this.leagueIds});

  final List<String>? leagueIds;

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  // Date du jour : celle de `todayProvider`, remise à jour quand le jour change (une app laissée
  // ouverte la nuit restait sur la veille : ces dates étaient `static`, calculées au lancement).
  late DateTime _today = ref.read(todayProvider);
  // Fenêtre ±14 jours (J8 : impossible d'aller plus loin que la date du jour
  // auparavant) fixe, indépendante du jour sélectionné — un seul appel API,
  // la liste montre toute la fenêtre d'un coup (voir `_AgendaList`).
  DateTime get _windowStart => _today.subtract(const Duration(days: 14));
  DateTime get _windowEnd => _today.add(const Duration(days: 14));
  DateTime get _minWeekStart => _mondayOf(_windowStart);
  DateTime get _maxWeekStart => _mondayOf(_windowEnd);

  late DateTime _weekStart = _mondayOf(_today);
  late DateTime _selectedDay = _today;
  String? _category;
  // `null` = tous les jeux de la catégorie "E-sport" (pas de restriction).
  Set<String>? _selectedLeagueIds;
  final _dayKeys = <DateTime, GlobalKey>{};

  static DateTime _mondayOf(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

  // Filtre repris tel quel à l'ouverture (J8) : sans ça, l'écran rouvre
  // toujours sur "Tout" même après avoir choisi "E-sport" la dernière fois.
  @override
  void initState() {
    super.initState();
    if (widget.leagueIds != null) return;
    final store = ref.read(authStoreProvider);
    _category = store.agendaCategory;
    final leagueIds = store.agendaLeagueIds;
    if (leagueIds != null && leagueIds.isNotEmpty) _selectedLeagueIds = leagueIds.split(",").toSet();
  }

  void _selectCategory(String? slug) {
    setState(() => _category = slug);
    _persistFilter();
  }

  void _persistFilter() {
    final leagueIds = _category == "esport" ? _selectedLeagueIds?.join(",") : null;
    ref.read(authStoreProvider).setAgendaFilter(category: _category, leagueIds: leagueIds);
  }

  void _selectDay(DateTime day) {
    setState(() => _selectedDay = day);
    final context = _dayKeys[day]?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  // Choix des jeux e-sport (une ligue racine par jeu, ex. "VCT" pour
  // Valorant) : une seule vraie entrée aujourd'hui, mais la feuille reste
  // correcte sans rien reconstruire dès qu'un 2e jeu sera ingéré.
  Future<void> _openEsportFilter() async {
    final roots = await ref.read(competitionRootsProvider("esport").future);
    if (!mounted) return;
    // Toujours le reflet exact du filtre actif : `null` = "Tous" (rien à
    // restreindre) → tout coché. Un pré-cochage "intelligent" différent de ce
    // qui est réellement appliqué (VCT par défaut, tenté puis retiré) induit
    // en erreur — mieux vaut rester cohérent, quitte à ce que "Fear Never
    // Ends" & co restent visibles tant que l'utilisateur n'a rien décoché.
    var working = _selectedLeagueIds ?? roots.map((r) => r.id).toSet();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("E-sport", style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Tous"),
                  value: working.length == roots.length,
                  onChanged: (checked) => setSheetState(() => working = checked == true ? roots.map((r) => r.id).toSet() : {}),
                ),
                for (final root in roots)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(root.name),
                    value: working.contains(root.id),
                    onChanged: (checked) => setSheetState(() {
                      if (checked == true) {
                        working.add(root.id);
                      } else {
                        working.remove(root.id);
                      }
                    }),
                  ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  onPressed: working.isEmpty ? null : () => Navigator.of(sheetContext).pop(true),
                  child: const Text("Appliquer"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _category = "esport";
      _selectedLeagueIds = working.length == roots.length ? null : working;
    });
    _persistFilter();
  }

  void _shiftWeek(int weeks) {
    setState(() {
      final shifted = _weekStart.add(Duration(days: 7 * weeks));
      if (shifted.isBefore(_minWeekStart)) {
        _weekStart = _minWeekStart;
      } else if (shifted.isAfter(_maxWeekStart)) {
        _weekStart = _maxWeekStart;
      } else {
        _weekStart = shifted;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Nouveau jour : la semaine et la sélection reprennent aujourd'hui.
    final today = ref.watch(todayProvider);
    if (today != _today) {
      _today = today;
      _weekStart = _mondayOf(today);
      _selectedDay = today;
      _dayKeys.clear();
    }
    final embedded = widget.leagueIds != null;
    final leagueIds = embedded ? widget.leagueIds!.toSet() : (_category == "esport" ? _selectedLeagueIds : null);
    final query = (from: _windowStart, to: _windowEnd, category: embedded ? null : _category, leagueIds: leagueIds?.isEmpty == true ? null : leagueIds?.join(","));
    final agenda = ref.watch(agendaProvider(query));
    final scoresHidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;

    return SafeArea(
      top: !embedded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!embedded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              child: Text("Agenda", style: Theme.of(context).textTheme.headlineLarge),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _WeekStrip(
            weekStart: _weekStart,
            selectedDay: _selectedDay,
            today: _today,
            minDay: _windowStart,
            maxDay: _windowEnd,
            canGoPrevious: _weekStart.isAfter(_minWeekStart),
            canGoNext: _weekStart.isBefore(_maxWeekStart),
            onPrevious: () => _shiftWeek(-1),
            onNext: () => _shiftWeek(1),
            onSelect: _selectDay,
          ),
          if (!embedded) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                for (final c in _categories) ...[
                  _CategoryPill(
                    label: c.slug == "esport" && (_selectedLeagueIds?.isNotEmpty ?? false)
                        ? "${c.label} (${_selectedLeagueIds!.length})"
                        : c.label,
                    selected: _category == c.slug,
                    onTap: () => c.slug == "esport" ? _openEsportFilter() : _selectCategory(c.slug),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
          ],
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: switch (agenda) {
              // Pendant un rechargement automatique, on garde l'ancien contenu (pas de spinner).
              _ when agenda.hasValue => _AgendaList(
                response: agenda.value!,
                scoresHidden: scoresHidden,
                dayKeys: _dayKeys,
                today: _today,
                filterKey: "${query.category}|${query.leagueIds}",
              ),
              AsyncError() => const Center(child: Text("Impossible de charger l'agenda.")),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: selected ? null : Border.all(color: AppColors.surfaceBorder),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 14, color: AppColors.background),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.background : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.weekStart,
    required this.selectedDay,
    required this.today,
    required this.minDay,
    required this.maxDay,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final DateTime weekStart;
  final DateTime selectedDay;
  final DateTime today;
  final DateTime minDay;
  final DateTime maxDay;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final dayLabels = DateFormat.E("fr_FR");
    // `IconButton` par défaut (48×48, cible tactile Material) : avec les 7
    // pastilles de jour (40 de large chacune, non compressibles) ça déborde
    // sur un écran étroit (360 de large logique, vérifié en conditions
    // réelles sur téléphone Android — débordement de 32 px, J8). Cible
    // réduite à 32×32, en dessous du minimum Material recommandé mais un
    // chevron reste facile à viser vu sa taille à l'écran.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(
            onPressed: canGoPrevious ? onPrevious : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.textSecondary,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 7; i++)
                  _WeekDay(
                    date: weekStart.add(Duration(days: i)),
                    label: dayLabels.format(weekStart.add(Duration(days: i))),
                    selected: _isSameDay(weekStart.add(Duration(days: i)), selectedDay),
                    isToday: _isSameDay(weekStart.add(Duration(days: i)), today),
                    enabled: !weekStart.add(Duration(days: i)).isBefore(minDay) && !weekStart.add(Duration(days: i)).isAfter(maxDay),
                    onTap: onSelect,
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: canGoNext ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: AppColors.textSecondary,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({
    required this.date,
    required this.label,
    required this.selected,
    required this.isToday,
    required this.enabled,
    required this.onTap,
  });

  final DateTime date;
  final String label;
  final bool selected;
  /// Repère visuel du jour courant, distinct du jour tapé/`selected` (celui
  /// qu'on peut faire défiler ailleurs dans la semaine) — rouge "tu es ici"
  /// comme les autres repères "où on en est" de l'appli (règle 12).
  final bool isToday;
  final bool enabled;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final dimmed = AppColors.textTertiary.withValues(alpha: 0.4);
    final dayColor = selected ? AppColors.background : (isToday ? AppColors.live : (enabled ? AppColors.textPrimary : dimmed));
    return InkWell(
      onTap: enabled ? () => onTap(date) : null,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        width: 36,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : null,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Column(
          children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 11, color: selected ? AppColors.background : (enabled ? AppColors.textTertiary : dimmed))),
            const SizedBox(height: 4),
            Text("${date.day}", style: TextStyle(fontWeight: FontWeight.w600, color: dayColor)),
            const SizedBox(height: 4),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: selected ? AppColors.background : (isToday ? AppColors.live : AppColors.textTertiary),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgendaList extends StatefulWidget {
  const _AgendaList({
    required this.response,
    required this.scoresHidden,
    required this.dayKeys,
    required this.today,
    required this.filterKey,
  });

  final AgendaResponseDto response;
  final bool scoresHidden;
  final Map<DateTime, GlobalKey> dayKeys;
  final DateTime today;
  // Catégorie + ligues choisies (`AgendaScreen.build`) : le jeu de jours
  // affiché change avec le filtre, donc la position à laquelle défiler aussi.
  final String filterKey;

  @override
  State<_AgendaList> createState() => _AgendaListState();
}

class _AgendaListState extends State<_AgendaList> {
  // Jours réellement affichés par le filtre actif (recalculé à chaque
  // `build`) : sert à retrouver le jour le plus proche d'aujourd'hui quand le
  // filtre n'a justement rien ce jour précis (ex. VCT seul, sans match
  // aujourd'hui) — `widget.dayKeys` seul ne suffit pas, il accumule des clés
  // d'anciens filtres jamais nettoyées.
  List<DateTime> _currentDays = const [];

  // Au premier montage avec de vraies données, puis à chaque fois que le
  // filtre change vraiment (`didUpdateWidget` ci-dessous) : si la réponse du
  // nouveau filtre arrive assez vite (cache), cette liste n'est jamais
  // recréée — juste mise à jour — et `initState` ne se redéclencherait pas
  // tout seul, laissant l'écran sur la position de l'ancien filtre.
  void _scrollToToday() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentDays.isEmpty) return;
      // Le jour exact s'il a un match, sinon le plus proche disponible dans
      // CE filtre (le futur le plus proche d'abord, sinon le passé récent).
      final target = _currentDays.contains(widget.today)
          ? widget.today
          : _currentDays.reduce((a, b) {
              final da = a.difference(widget.today).abs();
              final db = b.difference(widget.today).abs();
              if (da == db) return a.isAfter(widget.today) ? a : b;
              return da < db ? a : b;
            });
      final context = widget.dayKeys[target]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollToToday();
  }

  @override
  void didUpdateWidget(covariant _AgendaList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filterKey != oldWidget.filterKey) _scrollToToday();
  }

  @override
  Widget build(BuildContext context) {
    final response = widget.response;
    final scoresHidden = widget.scoresHidden;
    final dayKeys = widget.dayKeys;
    // Un match dont les équipes ne sont pas encore connues ("Decider Match:
    // TBD vs TBD", J5) n'a aucun `event_participant` en base tant que le
    // bracket ne l'a pas résolu : pas d'intérêt à l'afficher dans l'agenda
    // avant de savoir qui joue (le bracket, lui, le montre déjà en
    // placeholder — c'est voulu là-bas, pas ici).
    final events = response.events.where((e) => e.participants.isNotEmpty).toList();
    if (events.isEmpty) {
      _currentDays = const [];
      return const Center(child: Text("Rien à afficher pour l'instant.", style: TextStyle(color: AppColors.textSecondary)));
    }
    final byDay = <DateTime, List<EventSummaryDto>>{};
    for (final event in events) {
      final at = event.startsAt.toDateTime?.toLocal();
      if (at == null) continue;
      final day = DateTime(at.year, at.month, at.day);
      byDay.putIfAbsent(day, () => []).add(event);
    }
    final days = byDay.keys.toList()..sort();
    _currentDays = days;

    return ListView(
      // `cacheExtent` généreux : par défaut, une `ListView` (même avec une
      // liste `children:` classique, pas seulement `.builder`) ne construit
      // que les enfants proches de l'écran visible — le jour d'aujourd'hui,
      // hors de cette zone au premier affichage, n'avait donc jamais
      // d'`Element` monté, et `GlobalKey.currentContext` restait `null` pour
      // `Scrollable.ensureVisible` (vérifié en conditions réelles : la clé
      // existait bien, mais `currentContext` était `null`). Fenêtre ±14
      // jours bornée, un grand `cacheExtent` construit tout d'un coup sans
      // vrai souci de performance ici. 5000 (choisi au J8) ne couvrait que le
      // premier écran : dès qu'on scrollait plus loin qu'un tournoi chargé,
      // l'élément du jour visé ressortait de la fenêtre de cache et se
      // faisait détruire, laissant `_selectDay`/`_scrollToToday` sans
      // `currentContext` à cibler. Relevé à une valeur qui couvre toute la
      // fenêtre même un jour à beaucoup de matchs simultanés.
      // ponytail: valeur fixe plutôt qu'un calcul de hauteur réelle — si la
      // fenêtre s'agrandit un jour (> ±14 jours) ou que le volume de matchs
      // explose, remplacer par un `ScrollController` + offsets calculés.
      scrollCacheExtent: const ScrollCacheExtent.pixels(50000),
      // Bas généreux (64 de barre + marge ~8 + respiration) pour que la
      // dernière carte puisse défiler entièrement au-dessus de la tab bar
      // flottante (`GlassTabBar`) au lieu d'être coupée par elle.
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 96),
      children: [
        for (final day in days) ...[
          Column(
            key: dayKeys.putIfAbsent(day, () => GlobalKey()),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(_dayLabel(day), style: Theme.of(context).textTheme.labelSmall),
              ),
              // Chaque `EventCard` porte désormais sa propre bulle (fond,
              // bordure, teinte par couleur d'équipe) : plus de `Card`
              // englobante qui les aurait doublement encadrées.
              for (final event in byDay[day]!)
                EventCard(
                  event: event,
                  scoresHidden: scoresHidden,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static String _dayLabel(DateTime day) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final diff = day.difference(todayOnly).inDays;
    if (diff == 0) return "AUJOURD'HUI · ${DateFormat("EEE d", "fr_FR").format(day).toUpperCase()}";
    if (diff == 1) return "DEMAIN · ${DateFormat("EEE d", "fr_FR").format(day).toUpperCase()}";
    return DateFormat("EEEE d MMMM", "fr_FR").format(day).toUpperCase();
  }
}
