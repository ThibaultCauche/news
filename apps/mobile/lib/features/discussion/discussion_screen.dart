import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/auth/account.dart";
import "../../core/navigation.dart";
import "../../core/notifications/push_service.dart";
import "../../core/settings_provider.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/avatar_circle.dart";
import "../../widgets/empty_mark.dart";
import "../../widgets/page_title.dart";
import "../../widgets/section_label.dart";
import "../forum/forum_providers.dart";
import "../forum/thread_screen.dart";
import "../profile/groups_screen.dart";
import "ideas_screen.dart";

String _ago(DateTime date) {
  final d = DateTime.now().difference(date.toLocal());
  if (d.inMinutes < 1) return "à l'instant";
  if (d.inMinutes < 60) return "${d.inMinutes} min";
  if (d.inHours < 24) return "${d.inHours} h";
  return "${d.inDays} j";
}

const _kindLabels = {"event": "Match", "entity": "Équipe", "competition": "Compétition", "game": "Jeu", "free": "Discussion", "feature": "Idées"};

void _open(BuildContext context, WidgetRef ref, String threadId, String title) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ForumThreadScreen(threadId: threadId, title: title))).then((_) => ref.invalidate(inboxProvider));
}

/// Onglet « Discussion » (docs/04 J24) : ma boîte (fils de mes groupes, messages privés, discussions
/// suivies ou où j'ai écrit, avec non-lus), recherche de discussions publiques, nouveau message. Les fils
/// privés fonctionnent même quand le forum public reste en bêta fermée.
class DiscussionScreen extends ConsumerStatefulWidget {
  const DiscussionScreen({super.key});

  @override
  ConsumerState<DiscussionScreen> createState() => _DiscussionScreenState();
}

class _DiscussionScreenState extends ConsumerState<DiscussionScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = "";

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  Future<void> _newMessage() async {
    final controller = ref.read(forumControllerProvider);
    if (!await controller.ensureSignedIn() || !mounted) return;
    final contact = await showModalBottomSheet<ForumContactDto>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const _ContactPicker());
    if (contact == null || !mounted) return;
    try {
      final thread = await controller.openDm(contact.userId);
      if (mounted) _open(context, ref, thread.id, thread.title);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _openResult(ForumSearchResultDto result) async {
    try {
      var id = result.threadId;
      var title = result.title;
      if (id == null) {
        // Pas encore de fil : le serveur le crée à l'ouverture.
        final thread = await ref.read(forumThreadProvider((kind: result.kind.name, targetId: result.targetId)).future);
        if (thread == null) throw StateError("fil introuvable");
        id = thread.id;
        title = thread.title;
      }
      if (mounted) _open(context, ref, id, title);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(inboxProvider);
    await ref.read(inboxProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(signedInProvider);
    final forumOpen = ref.watch(forumEnabledProvider);
    // Les messages arrivent ici : à la première visite de l'onglet, on enregistre l'appareil pour les notifications
    // (sinon qui n'a jamais suivi un match ne recevrait aucun message privé).
    ref.listen(tabIndexProvider, (previous, next) {
      if (next == discussionTabIndex && previous != next && signedIn) ref.read(pushServiceProvider).ensureRegistered();
    });
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 120),
          children: [
            Row(
              children: [
                const Expanded(child: PageTitle("Discussion")),
                if (signedIn && forumOpen) IconButton(tooltip: "Boîte à idées", icon: const Icon(Icons.lightbulb_outline_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IdeasScreen()))),
                if (signedIn) IconButton(tooltip: "Nouveau message", icon: const Icon(Icons.edit_outlined), onPressed: _newMessage),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (!signedIn) _GuestCard(onSignIn: () => ref.read(forumControllerProvider).ensureSignedIn()) else ..._signedIn(context, forumOpen),
          ],
        ),
      ),
    );
  }

  List<Widget> _signedIn(BuildContext context, bool forumOpen) {
    final searching = forumOpen && _query.length >= 2;
    return [
      if (forumOpen)
        TextField(
          controller: _search,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: "Chercher une discussion…",
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = "");
                    },
                  ),
          ),
        ),
      const SizedBox(height: AppSpacing.md),
      if (searching) _results(context) else ..._inbox(context, forumOpen),
    ];
  }

  Widget _results(BuildContext context) {
    final results = ref.watch(forumSearchProvider(_query));
    return AsyncView(
      value: results,
      errorMessage: "Impossible de lancer la recherche.",
      compactError: true,
      onRetry: () => ref.invalidate(forumSearchProvider(_query)),
      skeleton: const SkeletonCards(count: 3, height: 56, padding: EdgeInsets.zero),
      builder: (value) => value.isEmpty
          ? const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: Text("Aucune discussion trouvée.", style: TextStyle(color: AppColors.textSecondary))))
          : Column(
              children: [
                for (final r in value)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(radius: 18, backgroundColor: AppColors.surfaceHighlight, child: Icon(Icons.forum_outlined, size: 18, color: AppColors.textSecondary)),
                    title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text("${_kindLabels[r.kind.name] ?? ""}${r.messageCount > 0 ? " · ${r.messageCount} message${r.messageCount > 1 ? "s" : ""}" : " · Sois le premier à écrire"}", style: const TextStyle(color: AppColors.textSecondary)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                    onTap: () => _openResult(r),
                  ),
              ],
            ),
    );
  }

  List<Widget> _inbox(BuildContext context, bool forumOpen) {
    final inbox = ref.watch(inboxProvider);
    return [
      AsyncView(
        value: inbox,
        errorMessage: "Impossible de charger tes discussions.",
        compactError: true,
        onRetry: () => ref.invalidate(inboxProvider),
        skeleton: const SkeletonCards(count: 4, height: 64, padding: EdgeInsets.zero),
        builder: (items) => items.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Column(
                  children: [
                    const EmptyMark("Rien ici pour l'instant. Écris à un ami de tes groupes, ou lance une discussion depuis un match."),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GroupsPage())), child: const Text("Mes groupes d'amis")),
                  ],
                ),
              )
            : Column(children: [for (final item in items) _InboxTile(item: item)]),
      ),
      if (forumOpen) ..._discover(inbox.value ?? const []),
    ];
  }

  // « À découvrir » : les discussions les plus actives du forum, hors celles déjà dans la boîte.
  List<Widget> _discover(List<InboxItemDto> inbox) {
    final threads = ref.watch(forumThreadsProvider((game: null, sort: "active", kind: null)));
    final mine = inbox.map((i) => i.thread.id).toSet();
    final list = (threads.value ?? const <ForumThreadDto>[]).where((t) => !mine.contains(t.id) && t.kind != ForumThreadDtoKindEnum.live).take(6).toList();
    if (list.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.lg),
      const SectionLabel("À DÉCOUVRIR"),
      const SizedBox(height: AppSpacing.xs),
      for (final t in list)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text("${_kindLabels[t.kind.name] ?? ""} · ${t.messageCount == 0 ? "Sois le premier à écrire" : "${t.messageCount} message${t.messageCount > 1 ? "s" : ""}"}", style: const TextStyle(color: AppColors.textSecondary)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          onTap: () => _open(context, ref, t.id, t.title),
        ),
    ];
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          const EmptyMark("Discute avec tes amis, partage un match, un pronostic. Un compte suffit."),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: onSignIn, child: const Text("Créer un compte ou me connecter")),
        ],
      ),
    );
  }
}

class _InboxTile extends ConsumerWidget {
  const _InboxTile({required this.item});

  final InboxItemDto item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = item.thread;
    final unread = item.unreadCount.toInt();
    final spoilerFree = ref.watch(userSettingProvider).value?.spoilerFree ?? false;
    // Un texte peut contenir un spoiler : en mode sans spoil, l'aperçu des messages libres est masqué.
    final preview = item.preview == null
        ? "Aucun message pour l'instant"
        : item.previewIsText && spoilerFree
            ? "Nouveau message"
            : item.previewFromMe
                ? "Toi : ${item.preview}"
                : (item.previewAuthor != null && thread.kind != ForumThreadDtoKindEnum.dm ? "${item.previewAuthor} : ${item.preview}" : item.preview!);
    final icon = switch (thread.kind) {
      ForumThreadDtoKindEnum.group => Icons.groups_outlined,
      ForumThreadDtoKindEnum.dm => Icons.person_outline_rounded,
      _ => Icons.forum_outlined,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: thread.kind == ForumThreadDtoKindEnum.dm
          ? AvatarCircle(avatarUrl: null, pseudo: thread.title, radius: 20)
          : CircleAvatar(radius: 20, backgroundColor: AppColors.surfaceHighlight, child: Icon(icon, size: 20, color: AppColors.textSecondary)),
      title: Text(thread.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: unread > 0 ? AppTextStyles.bodyLargeStrong : null),
      subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unread > 0 ? AppColors.textPrimary : AppColors.textSecondary)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (thread.lastMessageAt != null) Text(_ago(thread.lastMessageAt!), style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label)),
          if (thread.muted) const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.notifications_off_outlined, size: 14, color: AppColors.textTertiary)),
          if (unread > 0)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: AppColors.brass, borderRadius: BorderRadius.circular(AppRadii.pill)),
              child: Text(unread > 99 ? "99+" : "$unread", style: const TextStyle(color: AppColors.background, fontSize: AppTypography.label, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      onTap: () {
        // La boîte à idées a son propre écran (vote, statuts), pas celui d'un fil ordinaire.
        if (thread.kind == ForumThreadDtoKindEnum.feature) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IdeasScreen())).then((_) => ref.invalidate(inboxProvider));
        } else {
          _open(context, ref, thread.id, thread.title);
        }
      },
    );
  }
}

/// Choix du destinataire d'un nouveau message privé : les membres de mes groupes.
class _ContactPicker extends ConsumerWidget {
  const _ContactPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(forumContactsProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          children: [
            Text("Nouveau message", style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSpacing.xs),
            const Text("Tu peux écrire aux membres de tes groupes d'amis.", style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            AsyncView(
              value: contacts,
              errorMessage: "Impossible de charger tes contacts.",
              compactError: true,
              onRetry: () => ref.invalidate(forumContactsProvider),
              skeleton: const SkeletonCards(count: 3, height: 48, padding: EdgeInsets.zero),
              builder: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Column(
                        children: [
                          const Text("Personne pour l'instant : crée un groupe ou rejoins celui d'un ami avec son code.", style: TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(height: AppSpacing.sm),
                          OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GroupsPage()));
                            },
                            child: const Text("Mes groupes d'amis"),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (final c in list)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: AvatarCircle(avatarUrl: c.avatarUrl, pseudo: c.pseudo, radius: 18),
                            title: Text(c.pseudo),
                            onTap: () => Navigator.pop(context, c),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page « Mes groupes d'amis » (créer, rejoindre, ouvrir) : la section du Profil, accessible depuis la Discussion.
class GroupsPage extends ConsumerWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.md), children: const [GroupsSection()])),
    );
  }
}
