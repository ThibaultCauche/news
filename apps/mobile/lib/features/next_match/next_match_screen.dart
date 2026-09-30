import "dart:async";

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "package:url_launcher/url_launcher.dart";
import "../../core/api_providers.dart";
import "../../core/date_x.dart";
import "../../core/settings_provider.dart";
import "../../domain/event_status.dart";
import "../../theme/tokens.dart";
import "../learn/learn_screen.dart";
import "../../widgets/event_card.dart" show entityAccentColorProvider;
import "../../widgets/match_visuals.dart";
import "../../widgets/glossary_sheet.dart";
import "../../widgets/live_dot.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../follows/follows_provider.dart";
import "../team/team_screen.dart";
import "../../widgets/spoiler_hold.dart";
import "../profile/prediction_panel.dart";

final eventProvider = FutureProvider.autoDispose.family<EventDetailResponseDto, String>((ref, id) async {
  final response = await ref.watch(apiClientProvider).getEventsApi().eventsControllerGetById(id: id);
  return response.data!;
});

const _liveRefreshInterval = Duration(seconds: 20);
const _staleAfter = Duration(minutes: 15);

/// Écran 03/04/15 (`docs/02`) : compte à rebours ou score, "pourquoi ce match
/// compte" (`context.stakes`, mots en gras → feuille glossaire écran 04) et
/// forme récente/face-à-face (`context.recentForm`/`headToHead`, J6). Sans
/// spoil (écran 15) : masqué par défaut selon le réglage du compte, un appui
/// long sur le score le révèle pour la session (pas de mémorisation).
class NextMatchScreen extends ConsumerStatefulWidget {
  const NextMatchScreen({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<NextMatchScreen> createState() => _NextMatchScreenState();
}

class _NextMatchScreenState extends ConsumerState<NextMatchScreen> {
  Timer? _liveRefreshTimer;
  // `null` = pas de choix pour cette session, on suit le réglage du compte.
  bool? _scoresHiddenOverride;

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    super.dispose();
  }

  void _onStatusKnown(EventStatusKind status) {
    final shouldPoll = status == EventStatusKind.live;
    if (shouldPoll && _liveRefreshTimer == null) {
      _liveRefreshTimer = Timer.periodic(_liveRefreshInterval, (_) {
        ref.invalidate(eventProvider(widget.eventId));
      });
    } else if (!shouldPoll && _liveRefreshTimer != null) {
      _liveRefreshTimer?.cancel();
      _liveRefreshTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = ref.watch(eventProvider(widget.eventId));
    ref.listen(eventProvider(widget.eventId), (previous, next) {
      final value = next.value;
      if (value != null) _onStatusKnown(value.status.statusKind);
    });
    // Réglage global (J6) : une seule vraie catégorie avec des données pour
    // l'instant, la granularité par catégorie de l'écran 22 attendra une 2e
    // catégorie. `true` par défaut tant que le réglage n'est pas encore chargé.
    final defaultHidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    // Un score révélé par appui long sur sa carte l'est aussi ici (et inversement).
    final revealed = ref.watch(revealedEventsProvider).contains(widget.eventId);
    final scoresHidden = _scoresHiddenOverride ?? (defaultHidden && !revealed);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 160,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
          label: Text(
            event.value?.competition.name ?? "",
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        actions: [
          const LearnHelpButton(articleId: "regarder-un-match"),
          IconButton(
            icon: Icon(scoresHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            tooltip: "Sans spoil",
            onPressed: () => setState(() => _scoresHiddenOverride = !scoresHidden),
          ),
        ],
      ),
      body: switch (event) {
        // Pendant un rechargement automatique, on garde l'ancien contenu (pas de spinner).
        _ when event.hasValue =>
          _NextMatchBody(event: event.value!, scoresHidden: scoresHidden, onReveal: () => setState(() => _scoresHiddenOverride = false)),
        AsyncError() => const Center(child: Text("Impossible de charger ce match.")),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _NextMatchBody extends ConsumerWidget {
  const _NextMatchBody({required this.event, required this.scoresHidden, required this.onReveal});

  final EventDetailResponseDto event;
  final bool scoresHidden;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = event.status.statusKind;
    final isStale = status == EventStatusKind.live &&
        DateTime.now().difference(event.sourceUpdatedAt.toDateTime.toLocal()) > _staleAfter;

    // Même teinte par couleur d'équipe que la tuile de match (`EventCard`),
    // règle 12 : les mêmes visuels quel que soit l'écran.
    Color? accentOf(int index) {
      if (event.participants.length != 2) return null;
      final url = event.participants[index].imageUrl;
      if (url == null) return null;
      return ref.watch(entityAccentColorProvider(url)).value;
    }

    final colorA = accentOf(0);
    final colorB = accentOf(1);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (isStale) const _StaleBanner(),
        Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            gradient: teamsGradient(colorA, colorB),
          ),
          child: Column(
            children: [
              Text(
                [event.competition.name, if (event.bestOf != null) "BO${event.bestOf}"].join(" · ").toUpperCase(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              _Participants(event: event, scoresHidden: scoresHidden),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: GestureDetector(
            onLongPress: scoresHidden && status == EventStatusKind.finished
                ? () {}
                : null,
            // Score flouté : l'appui long le dissipe petit à petit (`SpoilerHold`), puis le révèle.
            child: scoresHidden && status == EventStatusKind.finished
                ? SpoilerHold(
                    builder: (context, sigma) => _StatusDisplay(event: event, scoresHidden: scoresHidden, sigma: sigma),
                    onReveal: () {
                      ref.read(revealedEventsProvider.notifier).reveal(event.id);
                      onReveal();
                    },
                  )
                : _StatusDisplay(event: event, scoresHidden: scoresHidden),
          ),
        ),
        if (scoresHidden && status == EventStatusKind.finished) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text("Maintiens pour révéler le score", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption)),
        ],
        const SizedBox(height: AppSpacing.lg),
        // Gagnant de chaque carte (règle 6 de CLAUDE.md) : masqué tant que le
        // score l'est aussi, même logique que `_StatusDisplay` — pas de
        // révélation séparée, le score et les cartes se démasquent ensemble.
        if (!scoresHidden && event.maps.any((m) => m.winnerEntityId != null)) ...[
          _MapsSection(event: event),
          const SizedBox(height: AppSpacing.md),
        ],
        if (event.context.stakes != null) ...[
          _StakesSection(stakes: event.context.stakes!),
          const SizedBox(height: AppSpacing.md),
        ],
        if (event.context.recentForm.isNotEmpty) ...[
          _RecentFormSection(event: event),
          const SizedBox(height: AppSpacing.md),
        ],
        PredictionPanel(event: event, scoresHidden: scoresHidden),
        const SizedBox(height: AppSpacing.md),
        if (status == EventStatusKind.scheduled) ...[
          _AlertButton(eventId: event.id),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Ajout à l'agenda bientôt disponible")),
              ),
              child: const Text("Ajouter à l'agenda"),
            ),
          ),
        ],
        // Recherche externe (pas un lien direct : impossible à calculer sans
        // l'identifiant interne du site tiers, ce qui reviendrait à le
        // scraper — règle 7 de CLAUDE.md). Masqué tant que le score l'est :
        // la page de résultats spoilerait un match qu'on masque nous-mêmes.
        if (event.participants.length == 2 && (status == EventStatusKind.scheduled || !scoresHidden)) _ExternalDetailsLink(event: event),
      ],
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: const Text(
        "Mise à jour en attente",
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

class _Participants extends StatelessWidget {
  const _Participants({required this.event, required this.scoresHidden});

  final EventDetailResponseDto event;
  final bool scoresHidden;

  @override
  Widget build(BuildContext context) {
    if (event.participants.length != 2) {
      return Text(event.name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final participant in event.participants)
          Expanded(child: _ParticipantColumn(participant: participant, competitionName: event.competition.name)),
      ],
    );
  }
}

/// Touche une équipe → sa fiche (écran 10, J6).
class _ParticipantColumn extends StatelessWidget {
  const _ParticipantColumn({required this.participant, required this.competitionName});

  final EventParticipantDto participant;
  final String competitionName;

  static const _diameter = 64.0;

  @override
  Widget build(BuildContext context) {
    final raw = participant.shortName ?? participant.name;
    final initials = (raw.length <= 3 ? raw : raw.substring(0, 3)).toUpperCase();
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.chip),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TeamScreen(entityId: participant.entityId, breadcrumb: competitionName)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          children: [
            TeamBadge(imageUrl: participant.imageUrl, diameter: _diameter, fallback: initials),
            const SizedBox(height: AppSpacing.sm),
            Text(participant.name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _StatusDisplay extends StatelessWidget {
  const _StatusDisplay({required this.event, required this.scoresHidden, this.sigma = 14});

  final EventDetailResponseDto event;
  final bool scoresHidden;

  /// Flou du score masqué (piloté par l'appui long) ; ignoré quand le score est visible.
  final double sigma;

  String? get _score {
    if (event.participants.length != 2) return null;
    final a = event.participants[0].score;
    final b = event.participants[1].score;
    if (a == null || b == null) return null;
    return "$a-$b";
  }

  @override
  Widget build(BuildContext context) {
    final status = event.status.statusKind;
    final textTheme = Theme.of(context).textTheme;
    return switch (status) {
      EventStatusKind.scheduled when event.startsAt.toDateTime != null => _Countdown(target: event.startsAt.toDateTime!.toLocal()),
      EventStatusKind.live => Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LiveDot(size: 12),
              const SizedBox(width: AppSpacing.sm),
              Text("EN DIRECT", style: textTheme.titleLarge?.copyWith(color: AppColors.live)),
            ],
          ),
          if (_score != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _AnimatedSpoiler(hidden: scoresHidden, sigma: sigma, child: Text(_score!, style: textTheme.headlineLarge)),
          ],
        ],
      ),
      EventStatusKind.finished => Column(
        children: [
          Text("Terminé", style: textTheme.bodyMedium),
          if (_score != null) _AnimatedSpoiler(hidden: scoresHidden, sigma: sigma, child: Text(_score!, style: textTheme.headlineLarge)),
        ],
      ),
      EventStatusKind.postponed => Text("Reporté", style: textTheme.titleLarge?.copyWith(color: AppColors.textTertiary)),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Score masqué = score flouté (J11, à la place des deux points) : le vrai texte sous un flou
/// qu'un appui long dissipe (`SpoilerHold`). Même gabarit masqué ou non, rien ne bouge.
class _AnimatedSpoiler extends StatelessWidget {
  const _AnimatedSpoiler({required this.hidden, required this.sigma, required this.child});

  final bool hidden;
  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) => SpoilerBlur(sigma: hidden ? sigma : 0, child: child);
}

/// Chiffres tabulaires, jamais animés (`docs/maquettes/motion-specs` — "60
/// fois par minute : jamais d'animation").
class _Countdown extends StatefulWidget {
  const _Countdown({required this.target});

  final DateTime target;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _timer;
  late Duration _remaining = widget.target.difference(DateTime.now());

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _remaining = widget.target.difference(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining.isNegative) {
      return const Text("Le match va bientôt commencer", style: TextStyle(color: AppColors.textSecondary));
    }
    final h = _remaining.inHours.toString().padLeft(2, "0");
    final m = (_remaining.inMinutes % 60).toString().padLeft(2, "0");
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, "0");
    return Column(
      children: [
        Text(
          "$h:$m:$s",
          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(_scheduleLabel(widget.target), style: const TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }

  static String _scheduleLabel(DateTime target) {
    final now = DateTime.now();
    final targetDay = DateTime(target.year, target.month, target.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = targetDay.difference(today).inDays;
    final day = switch (diff) {
      0 => "Aujourd'hui",
      1 => "Demain",
      _ => DateFormat("d MMMM", "fr_FR").format(target),
    };
    return "$day, ${DateFormat("H 'h' mm", "fr_FR").format(target)}";
  }
}

/// scale(0,97) à l'appui, devient "Alerte activée" au tap (`docs/maquettes/motion-specs`).
/// "M'alerter" suit l'événement (docs/04 J4) : rappel T-15, début, résultat.
class _AlertButton extends ConsumerStatefulWidget {
  const _AlertButton({required this.eventId});

  final String eventId;

  @override
  ConsumerState<_AlertButton> createState() => _AlertButtonState();
}

class _AlertButtonState extends ConsumerState<_AlertButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final activated = isFollowing(ref.watch(followsProvider).value, FollowTargetType.event, widget.eventId);
    // Un seul détecteur de tap : imbriquer un vrai `FilledButton` dans ce
    // `GestureDetector` ferait gagner son propre reconnaisseur dans l'arène
    // de gestes, et les callbacks ci-dessous ne se déclencheraient jamais.
    return GestureDetector(
      onTap: activated
          ? null
          : () {
              HapticFeedback.lightImpact();
              ref.read(followsControllerProvider).follow(FollowTargetType.event, widget.eventId);
            },
      onTapDown: activated ? null : (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: AppMotion.microDuration,
        curve: AppMotion.enter,
        child: SizedBox(
          width: double.infinity,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Container(
              key: ValueKey(activated),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(AppRadii.chip),
              ),
              alignment: Alignment.center,
              child: Text(
                activated ? "Alerte activée ✓" : "M'alerter au début du match",
                style: const TextStyle(color: AppColors.background, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renvoie vers une recherche Google restreinte à VLR.gg (round par round,
/// stats joueurs, noms de carte) : ce qu'on n'a pas le droit d'afficher
/// nous-mêmes vient d'une source qu'on a explicitement écartée pour l'appli
/// (`docs/01-donnees-sources-valorant.md` §4 — pas d'API officielle, pas de
/// droit de redistribution). VLR.gg n'a pas d'ID de match dérivable de nos
/// données (et sa propre recherche ne trouve rien sur une requête "A vs B",
/// vérifié) : impossible de lier la page exacte sans le scraper. Google
/// indexe déjà ces pages, donc une recherche `site:` y arrive presque
/// toujours, sans dépendre de la structure de VLR.gg.
class _ExternalDetailsLink extends StatelessWidget {
  const _ExternalDetailsLink({required this.event});

  final EventDetailResponseDto event;

  Uri get _searchUri {
    final teamA = event.participants[0].name;
    final teamB = event.participants[1].name;
    return Uri.https("www.google.com", "/search", {"q": 'site:vlr.gg "$teamA" "$teamB"'});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: TextButton.icon(
            onPressed: () => launchUrl(_searchUri, mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text("Plus de détails (hors de l'appli)"),
          ),
        ),
        // Pas juste "on n'a pas voulu" : la donnée existe, elle est payante
        // (docs/01-donnees-sources-valorant.md — PandaScore Historical, 400
        // €/mois) et hors de portée d'un projet non commercial pour l'instant.
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(
            "Stats round par round et par joueur : option payante (~400 €/mois) chez notre fournisseur de données. "
            "À revoir si l'appli grandit.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption),
          ),
        ),
      ],
    );
  }
}

/// Gagnant de chaque carte, rien de plus (règle 6 de CLAUDE.md — pas de score
/// en rounds, pas de nom de carte, limite du plan gratuit PandaScore).
class _MapsSection extends StatelessWidget {
  const _MapsSection({required this.event});

  final EventDetailResponseDto event;

  String _nameFor(String entityId) {
    final participant = event.participants.firstWhere((p) => p.entityId == entityId, orElse: () => event.participants.first);
    return participant.shortName ?? participant.name;
  }

  // "45:38", pas de nom de carte à côté (indisponible en plan gratuit) : la
  // durée est la seule information supplémentaire que PandaScore expose par
  // carte (docs/01-donnees-sources-valorant.md).
  static String _formatDuration(num seconds) {
    final total = seconds.toInt();
    final m = total ~/ 60;
    final s = total % 60;
    return "$m:${s.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    final maps = event.maps.where((m) => m.winnerEntityId != null).toList()..sort((a, b) => a.position.compareTo(b.position));
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("CARTES"),
          const SizedBox(height: AppSpacing.sm),
          for (final map in maps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Text("Carte ${map.position}", style: Theme.of(context).textTheme.bodyMedium),
                  if (map.durationSeconds != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Text(_formatDuration(map.durationSeconds!), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
                  ],
                  const Spacer(),
                  Text(_nameFor(map.winnerEntityId!), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Pourquoi ce match compte" (écran 03/04, `docs/03` §7) : phrase calculée par
/// des règles côté serveur (`context.stakes`), mots repérés `[[terme]]` rendus
/// en gras et ouvrant la feuille glossaire au toucher.
class _StakesSection extends StatelessWidget {
  const _StakesSection({required this.stakes});

  final String stakes;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("POURQUOI CE MATCH COMPTE"),
          const SizedBox(height: AppSpacing.sm),
          StakesText(text: stakes),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            "Touche un mot en gras pour l'explication.",
            style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption),
          ),
        ],
      ),
    );
  }
}

class StakesText extends StatefulWidget {
  const StakesText({super.key, required this.text});

  final String text;

  @override
  State<StakesText> createState() => _StakesTextState();
}

class _StakesTextState extends State<StakesText> {
  static final _termPattern = RegExp(r"\[\[(.+?)\]\]");

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _termPattern.allMatches(widget.text)) {
      if (match.start > cursor) spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      final term = match.group(1)!;
      final recognizer = TapGestureRecognizer()..onTap = () => showGlossarySheet(context, term);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: term,
          recognizer: recognizer,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      cursor = match.end;
    }
    if (cursor < widget.text.length) spans.add(TextSpan(text: widget.text.substring(cursor)));

    return Text.rich(TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: spans));
  }
}

/// Forme récente et face-à-face (écran 04, `docs/03` §7) : nos propres
/// `event`/`event_participant`, pas de source externe.
class _RecentFormSection extends StatelessWidget {
  const _RecentFormSection({required this.event});

  final EventDetailResponseDto event;

  @override
  Widget build(BuildContext context) {
    final headToHead = event.context.headToHead;
    String nameFor(String entityId) =>
        event.participants.firstWhere((p) => p.entityId == entityId, orElse: () => event.participants.first).shortName ?? "?";

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("FORME RÉCENTE"),
          const SizedBox(height: AppSpacing.xs),
          const Text("5 derniers", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption)),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in event.context.recentForm) ...[
            _FormRow(label: nameFor(entry.entityId), results: entry.results.toList()),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (headToHead != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Face-à-face  ${nameFor(headToHead.entityAId)} ${headToHead.entityAWins} – ${headToHead.entityBWins} ${nameFor(headToHead.entityBId)}",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({required this.label, required this.results});

  final String label;
  final List<String> results;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 48, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        const SizedBox(width: AppSpacing.sm),
        for (final result in results) ...[
          _FormDot(win: result == "V"),
          const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _FormDot extends StatelessWidget {
  const _FormDot({required this.win});

  final bool win;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: (win ? AppColors.win : AppColors.loss).withValues(alpha: win ? 0.18 : 0.12)),
      child: Text(
        win ? "V" : "D",
        style: TextStyle(color: win ? AppColors.win : AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}
