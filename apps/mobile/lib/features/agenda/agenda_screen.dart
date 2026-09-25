import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/date_x.dart";
import "../../theme/tokens.dart";
import "../../widgets/event_card.dart";
import "../next_match/next_match_screen.dart";

typedef AgendaQuery = ({DateTime from, DateTime to, String? category});

final agendaProvider = FutureProvider.autoDispose.family<AgendaResponseDto, AgendaQuery>((ref, query) async {
  final response = await ref.watch(apiClientProvider).getAgendaApi().agendaControllerGetAgenda(
    from: query.from.toUtc().toIso8601String(),
    to: query.to.toUtc().toIso8601String(),
    category: query.category,
  );
  return response.data!;
});

const _categories = [(label: "Tout", slug: null), (label: "E-sport", slug: "esport"), (label: "Sport", slug: "sport"), (label: "Politique", slug: "politique")];

/// Écran 09 (`docs/02`). L'export `.ics` de la maquette n'est pas prévu au
/// périmètre du J3 (`docs/04`) : le bouton reste visible mais désactivé.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  late DateTime _selectedDay = _dateOnly(DateTime.now());
  String? _category;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final weekStart = _selectedDay.subtract(Duration(days: _selectedDay.weekday - 1));
    final query = (from: _selectedDay, to: _selectedDay.add(const Duration(days: 14)), category: _category);
    final agenda = ref.watch(agendaProvider(query));

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Agenda", style: Theme.of(context).textTheme.headlineLarge),
                OutlinedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Export .ics bientôt disponible")),
                  ),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.textTertiary),
                  child: const Text("Exporter"),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text("Tout ce que tu suis, au même endroit", style: TextStyle(color: AppColors.textSecondary)),
          ),
          const SizedBox(height: AppSpacing.md),
          _WeekStrip(
            weekStart: weekStart,
            selectedDay: _selectedDay,
            onSelect: (day) => setState(() => _selectedDay = day),
          ),
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
                    selected: _category == c.slug,
                    onTap: () => setState(() => _category = c.slug),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
          Expanded(
            child: switch (agenda) {
              AsyncData(:final value) => _AgendaList(response: value),
              AsyncError() when agenda.hasValue => _AgendaList(response: agenda.value!),
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
  const _WeekStrip({required this.weekStart, required this.selectedDay, required this.onSelect});

  final DateTime weekStart;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final dayLabels = DateFormat.E("fr_FR");
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 7; i++)
            _WeekDay(
              date: weekStart.add(Duration(days: i)),
              label: dayLabels.format(weekStart.add(Duration(days: i))),
              selected: _isSameDay(weekStart.add(Duration(days: i)), selectedDay),
              onTap: onSelect,
            ),
        ],
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({required this.date, required this.label, required this.selected, required this.onTap});

  final DateTime date;
  final String label;
  final bool selected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(date),
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        width: 40,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : null,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Column(
          children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 11, color: selected ? AppColors.background : AppColors.textTertiary)),
            const SizedBox(height: 4),
            Text(
              "${date.day}",
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.background : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: selected ? AppColors.background : AppColors.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgendaList extends StatelessWidget {
  const _AgendaList({required this.response});

  final AgendaResponseDto response;

  @override
  Widget build(BuildContext context) {
    final events = response.events.toList();
    if (events.isEmpty) {
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
      children: [
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(_dayLabel(day), style: Theme.of(context).textTheme.labelSmall),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Column(
                children: [
                  for (final event in byDay[day]!)
                    EventCard(
                      event: event,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
                    ),
                ],
              ),
            ),
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
