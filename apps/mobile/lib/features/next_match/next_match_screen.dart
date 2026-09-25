import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/date_x.dart";
import "../../domain/event_status.dart";
import "../../theme/tokens.dart";
import "../../widgets/live_dot.dart";

final eventProvider = FutureProvider.autoDispose.family<EventDetailResponseDto, String>((ref, id) async {
  final response = await ref.watch(apiClientProvider).getEventsApi().eventsControllerGetById(id: id);
  return response.data!;
});

const _liveRefreshInterval = Duration(seconds: 20);
const _staleAfter = Duration(minutes: 15);

/// Écran 03 (`docs/02`). "Pourquoi ce match compte" et "Forme récente" ne
/// sont pas encore alimentés (`context_snippet` = J6, pas d'historique par
/// équipe) : ces blocs de la maquette n'apparaissent pas pour l'instant.
class NextMatchScreen extends ConsumerStatefulWidget {
  const NextMatchScreen({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<NextMatchScreen> createState() => _NextMatchScreenState();
}

class _NextMatchScreenState extends ConsumerState<NextMatchScreen> {
  Timer? _liveRefreshTimer;
  bool _scoresHidden = false;

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
            icon: Icon(_scoresHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            tooltip: "Sans spoil",
            onPressed: () => setState(() => _scoresHidden = !_scoresHidden),
          ),
        ],
      ),
      body: switch (event) {
        AsyncData(:final value) => _NextMatchBody(event: value, scoresHidden: _scoresHidden),
        AsyncError() when event.hasValue => _NextMatchBody(event: event.value!, scoresHidden: _scoresHidden),
        AsyncError() => const Center(child: Text("Impossible de charger ce match.")),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _NextMatchBody extends StatelessWidget {
  const _NextMatchBody({required this.event, required this.scoresHidden});

  final EventDetailResponseDto event;
  final bool scoresHidden;

  @override
  Widget build(BuildContext context) {
    final status = event.status.statusKind;
    final isStale = status == EventStatusKind.live &&
        DateTime.now().difference(event.sourceUpdatedAt.toDateTime.toLocal()) > _staleAfter;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (isStale) const _StaleBanner(),
        Text(
          [event.competition.name, if (event.bestOf != null) "BO${event.bestOf}"].join(" · ").toUpperCase(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        _Participants(event: event, scoresHidden: scoresHidden),
        const SizedBox(height: AppSpacing.lg),
        Center(child: _StatusDisplay(event: event, scoresHidden: scoresHidden)),
        const SizedBox(height: AppSpacing.lg),
        if (status == EventStatusKind.scheduled) ...[
          const _AlertButton(),
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
        for (final participant in event.participants) Expanded(child: _ParticipantColumn(participant: participant)),
      ],
    );
  }
}

class _ParticipantColumn extends StatelessWidget {
  const _ParticipantColumn({required this.participant});

  final EventParticipantDto participant;

  @override
  Widget build(BuildContext context) {
    final raw = participant.shortName ?? participant.name;
    final initials = (raw.length <= 3 ? raw : raw.substring(0, 3)).toUpperCase();
    return Column(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: AppColors.surface,
          child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(participant.name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      ],
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
/// Purement visuel pour l'instant : les abonnements/push arrivent au J4.
class _AlertButton extends StatefulWidget {
  const _AlertButton();

  @override
  State<_AlertButton> createState() => _AlertButtonState();
}

class _AlertButtonState extends State<_AlertButton> {
  bool _pressed = false;
  bool _activated = false;

  @override
  Widget build(BuildContext context) {
    // Un seul détecteur de tap : imbriquer un vrai `FilledButton` dans ce
    // `GestureDetector` ferait gagner son propre reconnaisseur dans l'arène
    // de gestes, et les callbacks ci-dessous ne se déclencheraient jamais.
    return GestureDetector(
      onTap: _activated
          ? null
          : () {
              HapticFeedback.lightImpact();
              setState(() => _activated = true);
            },
      onTapDown: _activated ? null : (_) => setState(() => _pressed = true),
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
              key: ValueKey(_activated),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(AppRadii.chip),
              ),
              alignment: Alignment.center,
              child: Text(
                _activated ? "Alerte activée ✓" : "M'alerter au début du match",
                style: const TextStyle(color: AppColors.background, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
