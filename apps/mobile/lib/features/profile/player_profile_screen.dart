import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/avatar_circle.dart";
import "community_providers.dart";
import "profile_screen.dart";

/// Profil d'un autre joueur (docs/04 J11, J13), ouvert depuis le classement d'un groupe ou depuis son
/// pseudo dans un fil du forum : avatar, pseudo, camps et stats de pronostics. Visible des membres d'un
/// groupe commun et de quiconque écrit sur le forum. Les stats
/// suivent le sans spoil de l'utilisateur (masquées jusqu'à un appui long).
class PlayerProfileScreen extends ConsumerWidget {
  const PlayerProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(userId));
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView(
        value: profile,
        errorMessage: "Impossible de charger ce profil.",
        onRetry: () => ref.invalidate(publicProfileProvider(userId)),
        builder: (value) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Row(
              children: [
                AvatarCircle(avatarUrl: value.avatarUrl, pseudo: value.pseudo, radius: 28),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(value.pseudo, style: AppTextStyles.pageTitle)),
              ],
            ),
            if (value.camps.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final camp in value.camps)
                    Chip(
                      avatar: camp.imageUrl == null ? null : AvatarCircle(avatarUrl: camp.imageUrl, radius: 10),
                      label: Text("${camp.name} · ${camp.game[0].toUpperCase()}${camp.game.substring(1)}"),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            StatsCard(stats: value.stats),
          ],
        ),
      ),
    );
  }
}
