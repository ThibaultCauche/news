import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../features/competitions/competitions_data.dart";
import "../features/follows/follows_provider.dart";
import "../theme/tokens.dart";
import "follow_button.dart";

/// "Suivre"/"Suivi" d'une page compétition (J10) : le désabonnement passe par ici
/// depuis que l'écran Suivis n'a plus de "x" — d'où sa place dans la barre du haut.
///
/// Une série couverte par un suivi de ligue ou de famille l'indique (« Suivi via VCT ») et
/// propose de ne plus être alerté pour celle-ci seulement (sourdine, « tout sauf une »).
class CompetitionFollowButton extends ConsumerWidget {
  const CompetitionFollowButton({super.key, required this.competitionId, required this.name});

  final String competitionId;
  final String name;

  /// Nom de la ligue ou de la famille suivie qui couvre cette série, sinon `null`.
  static String? _coveredBy(List<FollowStateDto>? follows, CatalogDto? catalog, String competitionId) {
    final found = findSerie(catalog, competitionId);
    if (found == null) return null;
    if (isFollowing(follows, FollowTargetType.competition, found.league.id)) return found.league.name;
    final familyId = found.serie.familyId;
    if (familyId != null && isFollowing(follows, FollowTargetType.competitionFamily, familyId)) {
      return found.league.families.where((f) => f.id == familyId).map((f) => f.name).firstOrNull;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final follows = ref.watch(followsProvider).value;
    final direct = isFollowing(follows, FollowTargetType.competition, competitionId);
    final muted = isMuted(follows, FollowTargetType.competition, competitionId);
    final via = direct ? null : _coveredBy(follows, ref.watch(catalogProvider).value, competitionId);
    final controller = ref.read(followsControllerProvider);

    Future<void> run(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
      } catch (_) {
        messenger.showSnackBar(const SnackBar(content: Text("Impossible de modifier ce suivi.")));
      }
    }

    final Widget button;
    if (via != null && muted) {
      button = FollowButton(
        following: false,
        label: "Réactiver les alertes",
        onPressed: () => run(() => controller.unfollow(FollowTargetType.competition, competitionId)),
      );
    } else if (via != null) {
      button = FollowButton(
        following: true,
        label: "Suivi via $via",
        onPressed: () => _confirmMute(context, via, () => run(() => controller.follow(FollowTargetType.competition, competitionId, name: name, muted: true))),
      );
    } else {
      button = FollowButton(
        following: direct,
        onPressed: () => run(
          () => direct
              ? controller.unfollow(FollowTargetType.competition, competitionId)
              : controller.follow(FollowTargetType.competition, competitionId, name: name),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: button)),
    );
  }

  static Future<void> _confirmMute(BuildContext context, String via, VoidCallback onConfirm) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Suivi via $via"),
        content: Text("Tu es alerté pour cette compétition parce que tu suis $via. Tu peux ne plus l'être pour celle-ci seulement."),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text("Annuler")),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onConfirm();
            },
            child: const Text("Ne pas m'alerter"),
          ),
        ],
      ),
    );
  }
}
