import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/avatar_circle.dart";
import "../../widgets/section_card.dart";
import "../competitions/competitions_data.dart";
import "../follows/follows_provider.dart";
import "forum_providers.dart";
import "forum_terms.dart";
import "thread_screen.dart";

/// Réglages du forum depuis le Profil (docs/04 J13) : camps, utilisateurs bloqués, conditions et,
/// pour un modérateur, la file de modération. Invisible quand le forum est fermé.
class ForumProfileSection extends ConsumerWidget {
  const ForumProfileSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(forumStatusProvider).value;
    if (status == null || !status.enabled) return const SizedBox.shrink();
    void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: SectionCard(
        child: Column(
          children: [
            _Row(icon: Icons.flag_outlined, label: "Mes camps", onTap: () => open(const CampsScreen())),
            const Divider(height: AppSpacing.lg),
            _Row(icon: Icons.block_outlined, label: "Utilisateurs bloqués", onTap: () => open(const BlockedUsersScreen())),
            const Divider(height: AppSpacing.lg),
            _Row(icon: Icons.gavel_outlined, label: "Conditions du forum", onTap: () => open(const ForumTermsScreen())),
            if (status.isModerator) ...[
              const Divider(height: AppSpacing.lg),
              _Row(icon: Icons.shield_outlined, label: "Modération", onTap: () => open(const ModerationScreen())),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: AppTextStyles.bodyLargeStrong)),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

/// Camps (badge du forum) : une équipe par jeu, choisie parmi celles qu'on suit, changeable une
/// fois par semaine.
class CampsScreen extends ConsumerWidget {
  const CampsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final camps = ref.watch(forumCampsProvider);
    final follows = ref.watch(followsProvider).value ?? const [];
    final followedTeams = follows.where((f) => f.targetType == "entity").toList();
    return Scaffold(
      appBar: AppBar(title: const Text("Mes camps")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const Text(
              "Ton camp s'affiche à côté de ton pseudo dans les discussions du jeu. Il se choisit parmi les équipes que tu suis, et se change une fois par semaine.",
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            switch (catalog) {
              AsyncData(:final value) => Column(
                children: [
                  for (final game in value.categories.expand((c) => c.games))
                    _GameCamp(
                      game: game,
                      current: camps.value?.where((c) => c.game == game.slug).firstOrNull,
                      followedTeams: followedTeams,
                    ),
                ],
              ),
              AsyncError() => const Text("Impossible de charger les jeux."),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ],
        ),
      ),
    );
  }
}

class _GameCamp extends ConsumerWidget {
  const _GameCamp({required this.game, required this.current, required this.followedTeams});

  final CatalogGameDto game;
  final ForumCampDto? current;
  final List<FollowStateDto> followedTeams;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    if (followedTeams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Suis d'abord une équipe pour en faire ton camp.")));
      return;
    }
    final picked = await showModalBottomSheet<FollowStateDto>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [for (final team in followedTeams) ListTile(title: Text(team.name), onTap: () => Navigator.pop(context, team))],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    try {
      await ref.read(forumControllerProvider).setCamp(game.slug, picked.targetId);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wait = current?.changeWaitDays.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SectionCard(
        child: Row(
          children: [
            AvatarCircle(avatarUrl: current?.imageUrl, pseudo: current?.name, radius: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(game.name, style: AppTextStyles.bodyLargeStrong),
                  Text(
                    current == null ? "Aucun camp" : (wait > 0 ? "${current!.name} · changement possible dans $wait j" : current!.name),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
                  ),
                ],
              ),
            ),
            if (current != null)
              IconButton(
                tooltip: "Retirer mon camp",
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => ref.read(forumControllerProvider).clearCamp(game.slug),
              ),
            TextButton(onPressed: wait > 0 ? null : () => _pick(context, ref), child: Text(current == null ? "Choisir" : "Changer")),
          ],
        ),
      ),
    );
  }
}

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = ref.watch(forumBlocksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Utilisateurs bloqués")),
      body: SafeArea(
        child: switch (blocks) {
          AsyncData(:final value) =>
            value.isEmpty
                ? const Center(child: Text("Tu n'as bloqué personne.", style: TextStyle(color: AppColors.textSecondary)))
                : ListView(
                    children: [
                      for (final user in value)
                        ListTile(
                          title: Text(user.pseudo),
                          trailing: TextButton(onPressed: () => ref.read(forumControllerProvider).unblock(user.userId), child: const Text("Débloquer")),
                        ),
                    ],
                  ),
          AsyncError() => const Center(child: Text("Impossible de charger la liste.")),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

const _reasonLabels = {"insult": "insulte", "spam": "spam", "spoiler": "spoiler", "other": "autre"};

/// File des messages signalés (modérateurs) : rejeter rend le message, masquer le confirme, exclure
/// retire la personne du forum.
class ModerationScreen extends ConsumerWidget {
  const ModerationScreen({super.key});

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(moderationReportsProvider);
    final controller = ref.read(forumControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Modération"),
        actions: [
          IconButton(
            tooltip: "Journal",
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ModerationLogScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (reports) {
          AsyncData(:final value) =>
            value.isEmpty
                ? const Center(child: Text("Aucun signalement à traiter.", style: TextStyle(color: AppColors.textSecondary)))
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      for (final report in value)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("${report.authorPseudo} · ${report.threadTitle}", style: AppTextStyles.bodyStrong),
                                const SizedBox(height: AppSpacing.xs),
                                Text(report.body),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  "${report.reportCount} signalement(s) : ${report.reasons.map((r) => _reasonLabels[r] ?? r).join(", ")}${report.hidden ? " · masqué" : ""}",
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
                                ),
                                Wrap(
                                  children: [
                                    TextButton(onPressed: () => _run(context, () => controller.dismissReports(report.messageId)), child: const Text("Rejeter")),
                                    TextButton(onPressed: () => _run(context, () => controller.hideMessage(report.messageId)), child: const Text("Masquer")),
                                    TextButton(
                                      onPressed: () => _run(context, () async {
                                        await controller.hideMessage(report.messageId);
                                        await controller.setBan(report.authorId, banned: true);
                                      }),
                                      child: const Text("Masquer et exclure", style: TextStyle(color: AppColors.live)),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ForumThreadScreen(threadId: report.threadId, title: report.threadTitle))),
                                      child: const Text("Voir le fil"),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          AsyncError() => const Center(child: Text("Impossible de charger la file.")),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

const _actionLabels = {
  "hide": "a masqué un message",
  "dismiss": "a rejeté les signalements d'un message",
  "ban": "a exclu",
  "unban": "a réintégré",
  "lock": "a verrouillé une discussion",
  "unlock": "a déverrouillé une discussion",
  "pin": "a épinglé un message",
  "unpin": "a désépinglé un message",
};

/// Journal de modération (modérateurs) : les 100 dernières décisions, qui, quoi, quand.
class ModerationLogScreen extends ConsumerWidget {
  const ModerationLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(moderationLogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Journal de modération")),
      body: SafeArea(
        child: switch (log) {
          AsyncData(:final value) =>
            value.isEmpty
                ? const Center(child: Text("Aucune décision pour l'instant.", style: TextStyle(color: AppColors.textSecondary)))
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      for (final entry in value)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${entry.moderatorPseudo ?? "Un modérateur"} ${_actionLabels[entry.action] ?? entry.action}${entry.targetPseudo == null ? "" : " · ${entry.targetPseudo}"}",
                                style: AppTextStyles.bodyStrong,
                              ),
                              if (entry.detail != null) Text("« ${entry.detail} »", style: const TextStyle(color: AppColors.textSecondary)),
                              Text(
                                DateFormat("d MMM, HH:mm", "fr_FR").format(entry.createdAt.toLocal()),
                                style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          AsyncError() => const Center(child: Text("Impossible de charger le journal.")),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}
