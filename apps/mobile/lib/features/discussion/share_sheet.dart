import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/avatar_circle.dart";
import "../forum/forum_providers.dart";
import "../profile/community_providers.dart";

/// Bouton « Partager » (J24) : ouvre la feuille « Envoyer à… » pour un match, une compétition ou un pronostic.
class ShareButton extends ConsumerWidget {
  const ShareButton({super.key, required this.kind, required this.refId});

  final ShareDtoKindEnum kind;
  final String refId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(tooltip: "Envoyer à…", icon: const Icon(Icons.ios_share_rounded), onPressed: () => showShareSheet(context, ref, kind: kind, refId: refId));
  }
}

/// Feuille « Envoyer à… » : mes groupes (fil du groupe) et les membres de mes groupes (message privé).
/// Seul l'identifiant part : le destinataire voit une carte à jour, avec son propre réglage sans spoil.
Future<void> showShareSheet(BuildContext context, WidgetRef ref, {required ShareDtoKindEnum kind, required String refId}) async {
  final controller = ref.read(forumControllerProvider);
  if (!await controller.ensureSignedIn() || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShareSheet(kind: kind, refId: refId),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.kind, required this.refId});

  final ShareDtoKindEnum kind;
  final String refId;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  // Un seul envoi à la fois ; les destinataires déjà servis restent cochés.
  bool _busy = false;
  final _sent = <String>{};

  Future<void> _send(String key, String name, Future<ForumThreadDto> Function() thread) async {
    if (_busy || _sent.contains(key)) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final target = await thread();
      await ref.read(forumControllerProvider).share(target.id, widget.kind, widget.refId);
      if (mounted) setState(() => _sent.add(key));
      messenger.showSnackBar(SnackBar(content: Text("Envoyé à $name.")));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(forumErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider);
    final contacts = ref.watch(forumContactsProvider);
    final controller = ref.read(forumControllerProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          shrinkWrap: true,
          children: [
            Text("Envoyer à…", style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSpacing.sm),
            if (groups.hasError || contacts.hasError)
              ErrorState(message: "Impossible de charger tes groupes.", onRetry: () {
                ref.invalidate(groupsProvider);
                ref.invalidate(forumContactsProvider);
              })
            else if (!groups.hasValue || !contacts.hasValue)
              const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (groups.value!.isEmpty && contacts.value!.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text("Crée un groupe d'amis ou rejoins-en un avec son code (Profil) pour pouvoir envoyer des cartes.", style: TextStyle(color: AppColors.textSecondary)),
              )
            else ...[
              for (final g in groups.value!)
                _Target(
                  leading: const CircleAvatar(radius: 16, backgroundColor: AppColors.surfaceHighlight, child: Icon(Icons.groups_outlined, size: 18, color: AppColors.textSecondary)),
                  title: g.name,
                  caption: "Groupe",
                  sent: _sent.contains("g:${g.id}"),
                  onTap: () => _send("g:${g.id}", g.name, () => controller.groupThread(g.id)),
                ),
              for (final c in contacts.value!)
                _Target(
                  leading: AvatarCircle(avatarUrl: c.avatarUrl, pseudo: c.pseudo, radius: 16),
                  title: c.pseudo,
                  caption: "Message privé",
                  sent: _sent.contains("u:${c.userId}"),
                  onTap: () => _send("u:${c.userId}", c.pseudo, () => controller.openDm(c.userId)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Target extends StatelessWidget {
  const _Target({required this.leading, required this.title, required this.caption, required this.sent, required this.onTap});

  final Widget leading;
  final String title;
  final String caption;
  final bool sent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(caption, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
      trailing: sent ? const Icon(Icons.check_rounded, color: AppColors.win) : const Icon(Icons.send_rounded, color: AppColors.textTertiary, size: 20),
      onTap: onTap,
    );
  }
}
