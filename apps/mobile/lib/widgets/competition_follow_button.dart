import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../features/follows/follows_provider.dart";
import "../theme/tokens.dart";
import "follow_button.dart";

/// "Suivre"/"Suivi" d'une page compétition (J10) : le désabonnement passe par ici
/// depuis que l'écran Suivis n'a plus de "x" — d'où sa place dans la barre du haut.
class CompetitionFollowButton extends ConsumerWidget {
  const CompetitionFollowButton({super.key, required this.competitionId, required this.name});

  final String competitionId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = isFollowing(ref.watch(followsProvider).value, FollowTargetType.competition, competitionId);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: Center(
        child: FollowButton(
          following: following,
          onPressed: () async {
            final controller = ref.read(followsControllerProvider);
            final messenger = ScaffoldMessenger.of(context);
            try {
              await (following
                  ? controller.unfollow(FollowTargetType.competition, competitionId)
                  : controller.follow(FollowTargetType.competition, competitionId, name: name));
            } catch (_) {
              messenger.showSnackBar(const SnackBar(content: Text("Impossible de modifier ce suivi.")));
            }
          },
        ),
      ),
    );
  }
}
