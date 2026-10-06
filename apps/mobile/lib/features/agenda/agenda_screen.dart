import "../../theme/app_theme.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart" show ScrollCacheExtent;
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../../widgets/page_title.dart";
import "../../core/api_providers.dart";
import "../../core/auth/account.dart";
import "../../core/clock.dart";
import "../../core/date_x.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/compact_match_row.dart";
import "../../widgets/match_context.dart";
import "../follows/follows_provider.dart";
import "../next_match/next_match_screen.dart";

typedef AgendaQuery = ({DateTime from, DateTime to, String? category, String? leagueIds, bool mine});

final agendaProvider = FutureProvider.autoDispose.family<AgendaResponseDto, AgendaQuery>((ref, query) async {
  final response = await ref.watch(apiClientProvider).getAgendaApi().agendaControllerGetAgenda(
    from: query.from.toUtc().toIso8601String(),
    to: query.to.toUtc().toIso8601String(),
    category: query.category,
    leagueIds: query.leagueIds,
    mine: query.mine ? "true" : null,
  );
  return response.data!;
});

/// Ligues racines d'une catégorie (un jeu = une ligue racine, ex. "VCT" pour
/// Valorant) : liste à cocher du filtre "E-sport" (`GET /v1/competitions/roots`).
final competitionRootsProvider = FutureProvider.autoDispose.family<List<CompetitionRootDto>, String>((ref, category) async {
  final response = await ref.watch(apiClientProvider).getCompetitionsApi().competitionsControllerGetRoots(category: category);
  return response.data!.toList();
});

// Catégories à sélection multiple (J22, #D3) : aucune cochée = tout. Icône seule si inactive, icône + nom si active (#D5).
const _categories = [
  (label: "E-sport", slug: "esport", icon: Icons.sports_esports_rounded),
  (label: "Sport", slug: "sport", icon: Icons.sports_soccer_rounded),
  (label: "Politique", slug: "politique", icon: Icons.account_balance_rounded),
];

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
  // Date autour de laquelle la fenêtre est chargée (J22, #D4) : aujourd'hui, ou le jour choisi dans le
  // calendrier. Fenêtre ±14 jours, un seul appel API, la liste montre toute la fenêtre d'un coup.
  late DateTime _anchor = _today;
  DateTime get _windowStart => _anchor.subtract(const Duration(days: 14));
  DateTime get _windowEnd => _anchor.add(const Duration(days: 14));
  DateTime get _minWeekStart => _mondayOf(_windowStart);
  DateTime get _maxWeekStart => _mondayOf(_windowEnd);

  late DateTime _weekStart = _mondayOf(_today);
  late DateTime _selectedDay = _today;
  final Set<String> _selectedCategories = {};
  // `null` = tous les jeux de la catégorie "E-sport" (pas de restriction).
  Set<String>? _selectedLeagueIds;
  // `null` = pas encore choisi : « Mes suivis » dès qu'on suit quelque chose, sinon « Tout ».
  bool? _mineChoice;
  final _dayKeys = <DateTime, GlobalKey>{};

  static DateTime _mondayOf(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

  // Filtre repris tel quel à l'ouverture (J8) : sans ça, l'écran rouvre
  // toujours sur "Tout" même après avoir choisi "E-sport" la dernière fois.
  @override
  void initState() {
    super.initState();
    if (widget.leagueIds != null) return;
    final store = ref.read(authStoreProvider);
    _selectedCategories.addAll((store.agendaCategory ?? "").split(",").where((c) => c.isNotEmpty));
    final leagueIds = store.agendaLeagueIds;
    if (leagueIds != null && leagueIds.isNotEmpty) _selectedLeagueIds = leagueIds.split(",").toSet();
    _mineChoice = store.agendaMine;
  }

  /// Les ligues ne restreignent que l'e-sport seul : avec une autre catégorie cochée, elles écarteraient son contenu.
  String? get _leagueRestriction => _selectedCategories.length == 1 && _selectedCategories.contains("esport") ? _selectedLeagueIds?.join(",") : null;

  String? get _categoryParam => _selectedCategories.isEmpty ? null : (_selectedCategories.toList()..sort()).join(",");

  void _toggleCategory(String slug) {
    setState(() => _selectedCategories.contains(slug) ? _selectedCategories.remove(slug) : _selectedCategories.add(slug));
    _persistFilter();
  }

  void _persistFilter() {
    // Les ligues choisies sont gardées même quand elles ne s'appliquent pas (e-sport + sport) : on les retrouve au retour à « E-sport » seul.
    ref.read(authStoreProvider).setAgendaFilter(category: _categoryParam, leagueIds: _selectedLeagueIds?.join(","));
  }

  void _selectMine(bool mine) {
    setState(() => _mineChoice = mine);
    ref.read(authStoreProvider).setAgendaMine(mine);
  }

  /// Retour à aujourd'hui (fenêtre, semaine et jour) après un saut dans le calendrier ou un défilement lointain.
  void _goToday() {
    setState(() {
      _anchor = _today;
      _weekStart = _mondayOf(_today);
      _selectedDay = _today;
      _dayKeys.clear();
    });
  }

  /// Jour voisin (balayage horizontal) : la semaine suit si on en sort, et on s'arrête aux bornes de la fenêtre.
  void _stepDay(int delta) {
    final next = _selectedDay.add(Duration(days: delta));
    final day = DateTime(next.year, next.month, next.day);
    if (day.isBefore(_windowStart) || day.isAfter(_windowEnd)) return;
    if (day.isBefore(_weekStart) || day.isAfter(_weekStart.add(const Duration(days: 6)))) setState(() => _weekStart = _mondayOf(day));
    _selectDay(day);
  }

  void _selectDay(DateTime day) {
    setState(() => _selectedDay = day);
    final context = _dayKeys[day]?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  AgendaQuery _queryFor(DateTime from, DateTime to, {required bool mine}) =>
      (from: from, to: to, category: _categoryParam, leagueIds: _leagueRestriction, mine: mine);

  // Calendrier du mois (J22, #D4) : un point les jours où il y a un match selon le filtre actif
  // (les suivis en « Mes suivis »). Choisir un jour recentre la fenêtre chargée sur lui.
  Future<void> _pickDate(bool mine) async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card))),
      builder: (_) => MonthCalendarSheet(initial: _selectedDay, today: _today, queryForMonth: (from, to) => _queryFor(from, to, mine: mine)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _anchor = DateTime(picked.year, picked.month, picked.day);
      _weekStart = _mondayOf(_anchor);
      _selectedDay = _anchor;
      _dayKeys.clear();
    });
  }

  // Choix des jeux e-sport (une ligue racine par jeu, ex. "VCT" pour
  // Valorant) : une seule vraie entrée aujourd'hui, mais la feuille reste
  // correcte sans rien reconstruire dès qu'un 2e jeu sera ingéré.
  Future<void> _openEsportFilter() async {
    final roots = await ref.read(competitionRootsProvider("esport").future);
    if (!mounted) return;
    // Toujours le reflet exact du filtre actif : `null` = "Tous" (rien à
    // restreindre) → tout coché.
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
                Text("E-sport", style: AppTextStyles.sectionTitle),
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
      _anchor = today;
      _weekStart = _mondayOf(today);
      _selectedDay = today;
      _dayKeys.clear();
    }
    final embedded = widget.leagueIds != null;
    final signedIn = ref.watch(signedInProvider);
    final hasFollows = (ref.watch(followsProvider).value ?? const []).isNotEmpty;
    final mine = !embedded && signedIn && (_mineChoice ?? hasFollows);
    final leagueIds = embedded ? widget.leagueIds!.toSet() : null;
    final AgendaQuery query = embedded
        ? (from: _windowStart, to: _windowEnd, category: null, leagueIds: leagueIds!.isEmpty ? null : leagueIds.join(","), mine: false)
        : _queryFor(_windowStart, _windowEnd, mine: mine);
    final agenda = ref.watch(agendaProvider(query));
    final scoresHidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;

    return SafeArea(
      top: !embedded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!embedded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.xs, 0),
              child: Row(
                children: [
                  // « Mes suivis / Tout » à droite du mot « Agenda », au-dessus du filet du titre.
                  Expanded(
                    child: Stack(
                      children: [
                        const PageTitle("Agenda"),
                        if (signedIn) Positioned(right: 0, top: 8, child: _MineToggle(mine: mine, onChanged: _selectMine)),
                      ],
                    ),
                  ),
                  IconButton(tooltip: "Choisir une date", onPressed: () => _pickDate(mine), icon: const Icon(Icons.calendar_month_rounded)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
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
                      label: c.label,
                      icon: c.icon,
                      selected: _selectedCategories.contains(c.slug),
                      // Seul le filtre des ligues e-sport a un second niveau (quel jeu).
                      onTune: c.slug == "esport" && _selectedCategories.contains("esport") ? _openEsportFilter : null,
                      onTap: () => _toggleCategory(c.slug),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  // Visible seulement quand on s'est éloigné d'aujourd'hui.
                  if (_selectedDay != _today || _anchor != _today) _TodayPill(onTap: _goToday),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: GestureDetector(
              // Balayage horizontal = jour précédent / suivant ; le défilement vertical de la liste n'est pas touché.
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v < -300) _stepDay(1);
                if (v > 300) _stepDay(-1);
              },
              child: switch (agenda) {
              // Pendant un rechargement automatique, on garde l'ancien contenu (pas de spinner).
              _ when agenda.hasValue => _AgendaList(
                response: agenda.value!,
                scoresHidden: scoresHidden,
                dayKeys: _dayKeys,
                focusDay: _anchor,
                filterKey: "${query.category}|${query.leagueIds}|$mine|${_anchor.toIso8601String()}",
                emptyMessage: mine ? "Rien dans tes suivis sur cette période." : "Rien à afficher pour l'instant.",
                onShowAll: mine ? () => _selectMine(false) : null,
              ),
              AsyncError() => ErrorState(message: "Impossible de charger l'agenda.", onRetry: () => ref.invalidate(agendaProvider(query))),
              _ => const SkeletonCards(count: 6, height: 64),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Bascule compacte « Mes suivis / Tout » : deux petites pastilles de 28 px, à la largeur de leur texte.
class _MineToggle extends StatelessWidget {
  const _MineToggle({required this.mine, required this.onChanged});

  final bool mine;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget segment(String label, bool value) {
      final selected = mine == value;
      return GestureDetector(
        onTap: () => onChanged(value),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? AppColors.brass : null, borderRadius: BorderRadius.circular(AppRadii.pill)),
          child: Text(label, style: TextStyle(fontSize: AppTypography.caption, fontWeight: FontWeight.w600, color: selected ? AppColors.background : AppColors.textSecondary)),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.pill), border: Border.all(color: AppColors.surfaceBorder)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [segment("Mes suivis", true), segment("Tout", false)]),
    );
  }
}

/// « Aujourd'hui » : ramène l'Agenda sur la date du jour.
class _TodayPill extends StatelessWidget {
  const _TodayPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Revenir à aujourd'hui",
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 2, vertical: AppSpacing.sm),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.pill), border: Border.all(color: AppColors.live.withValues(alpha: 0.7))),
          alignment: Alignment.center,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.today_rounded, size: 16, color: AppColors.live),
              SizedBox(width: 6),
              Text("Aujourd'hui", style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.live)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pastille de catégorie : icône seule quand inactive, icône + nom quand active (J22, #D5).
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label, required this.icon, required this.selected, required this.onTap, this.onTune});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onTune;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.background : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: selected ? AppSpacing.md : AppSpacing.sm + 4, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.brass : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: selected ? null : Border.all(color: AppColors.surfaceBorder),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              if (selected) ...[
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
              ],
              if (onTune != null) ...[
                const SizedBox(width: 6),
                GestureDetector(onTap: onTune, behavior: HitTestBehavior.opaque, child: Icon(Icons.tune_rounded, size: 16, color: color)),
              ],
            ],
          ),
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
          color: selected ? AppColors.brass : null,
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
    required this.focusDay,
    required this.filterKey,
    required this.emptyMessage,
    this.onShowAll,
  });

  final AgendaResponseDto response;
  final bool scoresHidden;
  final Map<DateTime, GlobalKey> dayKeys;
  // Jour sur lequel la liste se cale : aujourd'hui, ou la date choisie dans le calendrier.
  final DateTime focusDay;
  // Filtres + date choisie (`AgendaScreen.build`) : le jeu de jours
  // affiché change avec eux, donc la position à laquelle défiler aussi.
  final String filterKey;
  final String emptyMessage;
  final VoidCallback? onShowAll;

  @override
  State<_AgendaList> createState() => _AgendaListState();
}

class _AgendaListState extends State<_AgendaList> {
  // Jours réellement affichés par le filtre actif (recalculé à chaque
  // `build`) : sert à retrouver le jour le plus proche du jour visé quand le
  // filtre n'a justement rien ce jour précis — `widget.dayKeys` seul ne suffit
  // pas, il accumule des clés d'anciens filtres jamais nettoyées.
  List<DateTime> _currentDays = const [];

  // Faux tant que la liste n'est pas calée sur son jour : elle reste invisible ce premier instant, pour
  // qu'on ne voie ni le haut de la liste ni un défilement (le saut est immédiat, sans animation).
  bool _positioned = false;

  // Au premier montage avec de vraies données, puis à chaque fois que le
  // filtre change vraiment (`didUpdateWidget` ci-dessous) : si la réponse du
  // nouveau filtre arrive assez vite (cache), cette liste n'est jamais
  // recréée — juste mise à jour — et `initState` ne se redéclencherait pas
  // tout seul, laissant l'écran sur la position de l'ancien filtre.
  void _scrollToFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_currentDays.isEmpty) {
        setState(() => _positioned = true);
        return;
      }
      final focus = widget.focusDay;
      // Le jour exact s'il a un match, sinon le plus proche disponible dans
      // CE filtre (le futur le plus proche d'abord, sinon le passé récent).
      final target = _currentDays.contains(focus)
          ? focus
          : _currentDays.reduce((a, b) {
              final da = a.difference(focus).abs();
              final db = b.difference(focus).abs();
              if (da == db) return a.isAfter(focus) ? a : b;
              return da < db ? a : b;
            });
      final context = widget.dayKeys[target]?.currentContext;
      if (context != null) Scrollable.ensureVisible(context); // saut direct : un défilement sur des semaines ferait mal aux yeux
      setState(() => _positioned = true);
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollToFocus();
  }

  @override
  void didUpdateWidget(covariant _AgendaList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filterKey != oldWidget.filterKey) {
      _positioned = false;
      _scrollToFocus();
    }
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.emptyMessage, style: const TextStyle(color: AppColors.textSecondary)),
            if (widget.onShowAll != null) TextButton(onPressed: widget.onShowAll, child: const Text("Voir tout l'agenda")),
          ],
        ),
      );
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

    return Opacity(
      opacity: _positioned ? 1 : 0,
      child: CustomScrollView(
      // `cacheExtent` généreux : par défaut, une liste ne construit que les enfants proches de
      // l'écran visible — le jour visé, hors de cette zone au premier affichage, n'avait donc
      // jamais d'`Element` monté, et `GlobalKey.currentContext` restait `null` pour
      // `Scrollable.ensureVisible`. Fenêtre ±14 jours bornée : tout construire d'un coup reste bon marché.
      // ponytail: valeur fixe plutôt qu'un calcul de hauteur réelle — si la
      // fenêtre s'agrandit un jour (> ±14 jours) ou que le volume de matchs
      // explose, remplacer par un `ScrollController` + offsets calculés.
      scrollCacheExtent: const ScrollCacheExtent.pixels(50000),
      slivers: [
        for (final day in days) ...[
          SliverToBoxAdapter(
            child: Padding(
              key: dayKeys.putIfAbsent(day, () => GlobalKey()),
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
              child: Text(_dayLabel(day), style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
          // Un groupe par compétition, son en-tête reste collé en haut tant que ses matchs défilent (#A3).
          for (final (competition, matches) in groupByCompetition(byDay[day]!))
            SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(pinned: true, delegate: CompetitionHeaderDelegate(competition)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                  sliver: SliverList.separated(
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) => CompactMatchRow(
                      event: matches[i],
                      scoresHidden: scoresHidden,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: matches[i].id))),
                    ),
                  ),
                ),
              ],
            ),
        ],
        // Bas généreux (64 de barre + marge ~8 + respiration) pour que la dernière ligne puisse
        // défiler entièrement au-dessus de la tab bar flottante (`GlassTabBar`).
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
      ),
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

/// Jours qui ont au moins un match (heure locale) : les points du calendrier (J22, #D4).
Set<DateTime> daysWithMatches(Iterable<EventSummaryDto> events) {
  final days = <DateTime>{};
  for (final event in events) {
    final at = event.startsAt.toDateTime?.toLocal();
    if (at != null && event.participants.isNotEmpty) days.add(DateTime(at.year, at.month, at.day));
  }
  return days;
}

/// Calendrier du mois en feuille : un point sous les jours où il y a un match selon le filtre actif.
/// Renvoie le jour choisi.
class MonthCalendarSheet extends ConsumerStatefulWidget {
  const MonthCalendarSheet({super.key, required this.initial, required this.today, required this.queryForMonth});

  final DateTime initial;
  final DateTime today;
  final AgendaQuery Function(DateTime from, DateTime to) queryForMonth;

  @override
  ConsumerState<MonthCalendarSheet> createState() => _MonthCalendarSheetState();
}

class _MonthCalendarSheetState extends ConsumerState<MonthCalendarSheet> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);

  @override
  Widget build(BuildContext context) {
    final from = _month;
    final to = DateTime(_month.year, _month.month + 1);
    final agenda = ref.watch(agendaProvider(widget.queryForMonth(from, to)));
    final dots = agenda.hasValue ? daysWithMatches(agenda.value!.events) : const <DateTime>{};
    final leading = _month.weekday - 1; // lundi en premier
    final daysInMonth = to.difference(from).inDays;
    final dayLabels = DateFormat.E("fr_FR");
    final monday = DateTime(2024, 1, 1);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(tooltip: "Mois précédent", onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: Text(
                    toBeginningOfSentenceCase(DateFormat("MMMM y", "fr_FR").format(_month)),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.sectionTitle,
                  ),
                ),
                IconButton(tooltip: "Mois suivant", onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Text(dayLabels.format(monday.add(Duration(days: i))).toUpperCase(), style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.1,
              children: [
                for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                for (var d = 1; d <= daysInMonth; d++)
                  _CalendarDay(
                    day: DateTime(_month.year, _month.month, d),
                    isToday: DateTime(_month.year, _month.month, d) == widget.today,
                    selected: DateTime(_month.year, _month.month, d) == widget.initial,
                    hasMatch: dots.contains(DateTime(_month.year, _month.month, d)),
                    onTap: (day) => Navigator.of(context).pop(day),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({required this.day, required this.isToday, required this.selected, required this.hasMatch, required this.onTap});

  final DateTime day;
  final bool isToday;
  final bool selected;
  final bool hasMatch;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(day),
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: selected ? AppColors.brass : null, borderRadius: BorderRadius.circular(AppRadii.chip)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("${day.day}", style: TextStyle(fontWeight: FontWeight.w600, color: selected ? AppColors.background : (isToday ? AppColors.live : AppColors.textPrimary))),
            const SizedBox(height: 3),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(color: hasMatch ? (selected ? AppColors.background : AppColors.gold) : Colors.transparent, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}
