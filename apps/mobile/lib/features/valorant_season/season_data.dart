import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/date_x.dart";
import "../../core/iterable_x.dart";

class SeasonStep {
  const SeasonStep({required this.id, required this.name, required this.status, required this.startsAt, required this.endsAt, this.hasEvents = true});

  final String id;
  final String name;
  final String? status;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// `false` pour une étape passée dont plus aucun match n'est en base : sa page serait vide, on ne la liste pas.
  final bool hasEvents;

  bool get isMasters => name.toLowerCase().contains("masters");
}

class SeasonOverview {
  const SeasonOverview({
    required this.rootCompetitionId,
    required this.steps,
    required this.currentStep,
    required this.progress,
    required this.currentMatches,
    required this.playedSteps,
    required this.liquipediaContext,
  });

  /// Ligue racine (ex. "VCT") : cible du bouton "Suivre" de l'écran (docs/04 J4)
  /// — suivre la saison entière plutôt qu'une seule étape.
  final String rootCompetitionId;
  final List<SeasonStep> steps;
  final SeasonStep currentStep;
  final double progress;
  final List<EventSummaryDto> currentMatches;
  final List<SeasonStep> playedSteps;

  /// Contexte Liquipedia de l'étape en cours (ex. "Champions 2026"), `null` tant
  /// que le job worker ne l'a pas encore trouvé (docs/03 §7, J6).
  final CompetitionContextDto? liquipediaContext;
}

/// Écran 01 (`docs/02`). L'API ne fournit ni recherche ni id de saison tout
/// prêt (J2 n'a construit que `home`/`agenda`/`events/:id`/`competitions/:id`) :
/// on part d'un match Valorant connu (via l'agenda) et on remonte
/// l'arborescence des compétitions (`parentId`) jusqu'à la ligue racine, dont
/// les enfants sont les étapes de la saison (Kickoff, Stages, Masters,
/// Champions — mélangeant 2025 et 2026, filtrées par nom).
final valorantSeasonProvider = FutureProvider.autoDispose<SeasonOverview?>((ref) async {
  final api = ref.watch(apiClientProvider);
  final now = DateTime.now();

  Future<CompetitionResponseDto> fetchCompetition(String id) async {
    final response = await api.getCompetitionsApi().competitionsControllerGetById(id: id);
    return response.data!;
  }

  final entryWindow = await api.getAgendaApi().agendaControllerGetAgenda(
    from: now.subtract(const Duration(days: 14)).toUtc().toIso8601String(),
    to: now.add(const Duration(days: 60)).toUtc().toIso8601String(),
    category: "esport",
  );
  final entryEvent = entryWindow.data?.events.toList().firstOrNull;
  if (entryEvent == null) return null;

  var node = await fetchCompetition(entryEvent.competition.id);
  while (node.parentId != null) {
    node = await fetchCompetition(node.parentId!);
  }
  final root = node; // ligue racine (ex. "VCT"), ses enfants sont les séries.

  final seasonChildren = root.children.where((c) => c.name.contains("2026")).toList()
    ..sort(_byStartsAt);
  if (seasonChildren.isEmpty) return null;

  final steps = [
    for (final c in seasonChildren)
      SeasonStep(id: c.id, name: c.name, status: c.status, startsAt: c.startsAt.toDateTime, endsAt: c.endsAt.toDateTime, hasEvents: c.hasEvents),
  ];

  final currentStep = _pickCurrentStep(steps, now);

  final currentStepDetail = await fetchCompetition(currentStep.id);
  final tournamentIds = {currentStep.id, ...currentStepDetail.children.map((c) => c.id)};

  final focusedAgenda = await api.getAgendaApi().agendaControllerGetAgenda(
    from: now.subtract(const Duration(days: 3)).toUtc().toIso8601String(),
    to: now.add(const Duration(days: 14)).toUtc().toIso8601String(),
    category: "esport",
  );
  final currentMatches = (focusedAgenda.data?.events.toList() ?? const <EventSummaryDto>[])
      .where((e) => tournamentIds.contains(e.competition.id))
      .toList()
    ..sort((a, b) => (a.startsAt.toDateTime ?? now).compareTo(b.startsAt.toDateTime ?? now));

  final playedSteps = steps
      .where((s) => s.id != currentStep.id && s.hasEvents && (s.endsAt ?? s.startsAt ?? now).isBefore(now))
      .toList();

  return SeasonOverview(
    rootCompetitionId: root.id,
    steps: steps,
    currentStep: currentStep,
    progress: _seasonProgress(steps, now),
    currentMatches: currentMatches,
    playedSteps: playedSteps,
    liquipediaContext: currentStepDetail.context,
  );
});

int _byStartsAt(CompetitionChildDto a, CompetitionChildDto b) {
  final far = DateTime(2100);
  final aStart = a.startsAt.toDateTime ?? far;
  final bStart = b.startsAt.toDateTime ?? far;
  return aStart.compareTo(bStart);
}

SeasonStep _pickCurrentStep(List<SeasonStep> steps, DateTime now) {
  for (final s in steps) {
    if (s.status == "live") return s;
  }
  for (final s in steps) {
    if (s.startsAt != null && s.endsAt != null && !now.isBefore(s.startsAt!) && !now.isAfter(s.endsAt!)) return s;
  }
  for (final s in steps) {
    if (s.startsAt != null && s.startsAt!.isAfter(now)) return s;
  }
  return steps.last;
}

double _seasonProgress(List<SeasonStep> steps, DateTime now) {
  final firstStart = steps.first.startsAt;
  final lastEnd = steps.last.endsAt ?? steps.last.startsAt;
  if (firstStart == null || lastEnd == null || !lastEnd.isAfter(firstStart)) return 0;
  final ratio = now.difference(firstStart).inMinutes / lastEnd.difference(firstStart).inMinutes;
  return ratio.clamp(0, 1);
}
