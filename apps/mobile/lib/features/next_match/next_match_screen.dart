import "dart:async";

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/date_x.dart";
import "../../core/settings_provider.dart";
import "../../domain/event_status.dart";
import "../../theme/tokens.dart";
import "../../widgets/event_card.dart" show entityAccentColorProvider;
import "../../widgets/glossary_sheet.dart";
import "../../widgets/live_dot.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../follows/follows_provider.dart";
import "../team/team_screen.dart";

final eventProvider = FutureProvider.autoDispose.family<EventDetailResponseDto, String>((ref, id) async {
  final response = await ref.watch(apiClientProvider).getEventsApi().eventsControllerGetById(id: id);
  return response.data!;
});

const _liveRefreshInterval = Duration(seconds: 20);
const _staleAfter = Duration(minutes: 15);

/// Écran 03/04/15 (`docs/02`) : compte à rebours ou score, "pourquoi ce match
/// compte" (`context.stakes`, mots soulignés → feuille glossaire écran 04) et
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
    final scoresHidden = _scoresHiddenOverride ?? defaultHidden;

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
          IconButton(
            icon: Icon(scoresHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            tooltip: "Sans spoil",
            onPressed: () => setState(() => _scoresHiddenOverride = !scoresHidden),
          ),
        ],
      ),
      body: switch (event) {
        AsyncData(:final value) => _NextMatchBody(event: value, scoresHidden: scoresHidden, onReveal: () => setState(() => _scoresHiddenOverride = false)),
        AsyncError() when event.hasValue =>
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
            gradient: (colorA == null && colorB == null)
                ? null
                : LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      (colorA ?? AppColors.surface).withValues(alpha: colorA != null ? 0.26 : 0),
                      AppColors.surface,
                      (colorB ?? AppColors.surface).withValues(alpha: colorB != null ? 0.26 : 0),
                    ],
                  ),
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
                ? () {
                    HapticFeedback.mediumImpact();
                    onReveal();
                  }
                : null,
            child: _StatusDisplay(event: event, scoresHidden: scoresHidden),
          ),
        ),
        if (scoresHidden && status == EventStatusKind.finished) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text("Toucher longuement pour révéler", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption)),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (event.context.stakes != null) ...[
          _StakesSection(stakes: event.context.stakes!),
          const SizedBox(height: AppSpacing.md),
        ],
        if (event.context.recentForm.isNotEmpty) ...[
          _RecentFormSection(event: event),
          const SizedBox(height: AppSpacing.md),
        ],
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
            ClipOval(
              child: Container(
                width: _diameter,
                height: _diameter,
                color: AppColors.surface,
                alignment: Alignment.center,
                // `BoxFit.contain`, pas `cover` : les logos ne sont pas tous
                // carrés (même logique que `EventCard`/`_TeamBadge`).
                child: participant.imageUrl != null
                    ? Image.network(participant.imageUrl!, fit: BoxFit.contain)
                    : Text(initials, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(participant.name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _StatusDisplay extends StatelessWidget {
  const _StatusDisplay({required this.event, required this.scoresHidden});

  final EventDetailResponseDto event;
  final bool scoresHidden;

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
            _AnimatedSpoiler(hidden: scoresHidden, child: Text(_score!, style: textTheme.headlineLarge)),
          ],
        ],
      ),
      EventStatusKind.finished => Column(
        children: [
          Text("Terminé", style: textTheme.bodyMedium),
          if (_score != null) _AnimatedSpoiler(hidden: scoresHidden, child: Text(_score!, style: textTheme.headlineLarge)),
        ],
      ),
      EventStatusKind.postponed => Text("Reporté", style: textTheme.titleLarge?.copyWith(color: AppColors.textTertiary)),
      _ => const SizedBox.shrink(),
    };
  }
}

/// "Scores masqués ↔ visibles en fondu 150 ms, rien ne bouge" (`docs/maquettes/motion-specs`).
class _AnimatedSpoiler extends StatelessWidget {
  const _AnimatedSpoiler({required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 150),
      crossFadeState: hidden ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstChild: Text("•  •", style: Theme.of(context).textTheme.headlineLarge),
      secondChild: child,
    );
  }
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

/// "Pourquoi ce match compte" (écran 03/04, `docs/03` §7) : phrase calculée par
/// des règles côté serveur (`context.stakes`), mots repérés `[[terme]]` rendus
/// soulignés et ouvrant la feuille glossaire au toucher.
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
          _StakesText(text: stakes),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            "Touche un mot souligné pour l'explication.",
            style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption),
          ),
        ],
      ),
    );
  }
}

class _StakesText extends StatefulWidget {
  const _StakesText({required this.text});

  final String text;

  @override
  State<_StakesText> createState() => _StakesTextState();
}

class _StakesTextState extends State<_StakesText> {
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
          style: const TextStyle(decoration: TextDecoration.underline, decorationColor: AppColors.textSecondary),
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
