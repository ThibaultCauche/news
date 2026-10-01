import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/live_dot.dart";
import "../../widgets/section_card.dart";
import "forum_providers.dart";
import "thread_screen.dart";

void openThread(BuildContext context, ForumThreadDto thread) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ForumThreadScreen(threadId: thread.id, title: thread.title)));
}

String _messagesLabel(int count) => count == 0 ? "Sois le premier à écrire" : (count == 1 ? "1 message" : "$count messages");

/// Carte « Discussion » d'un match, d'une équipe ou d'une compétition (docs/04 J13) : ouvre le fil,
/// créé à la première ouverture. Invisible quand le forum est fermé (bêta) ou la cible inconnue.
class ForumEntryCard extends ConsumerWidget {
  const ForumEntryCard({super.key, required this.kind, required this.targetId, this.label = "Discussion", this.liveDot = false});

  final String kind;
  final String targetId;
  final String label;
  // Point rouge « en direct » à la place de l'icône (fil du direct d'un match en cours).
  final bool liveDot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(forumThreadProvider((kind: kind, targetId: targetId))).value;
    if (thread == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: () => openThread(context, thread),
        child: SectionCard(
          child: Row(
            children: [
              if (liveDot) const SizedBox(width: 24, child: Center(child: LiveDot(size: 10))) else const Icon(Icons.forum_outlined, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.bodyLargeStrong),
                    Text("${thread.kind == ForumThreadDtoKindEnum.live ? (thread.readOnly ? "Direct terminé · " : "En direct · ") : ""}${_messagesLabel(thread.messageCount.toInt())}", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icône « discussion » de la barre d'une page (compétition) : même fil que [ForumEntryCard].
class ForumActionButton extends ConsumerWidget {
  const ForumActionButton({super.key, required this.kind, required this.targetId});

  final String kind;
  final String targetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(forumThreadProvider((kind: kind, targetId: targetId))).value;
    if (thread == null) return const SizedBox.shrink();
    return IconButton(tooltip: "Discussion", icon: const Icon(Icons.forum_outlined), onPressed: () => openThread(context, thread));
  }
}

/// Onglet « Discussions » d'un jeu : la discussion générale du jeu, celles des matchs, équipes et
/// compétitions où l'on écrit, et les discussions libres que les utilisateurs ouvrent. Tri (récentes,
/// actives, populaires) et filtre par type.
class ForumThreadsTab extends ConsumerStatefulWidget {
  const ForumThreadsTab({super.key, required this.game, required this.gameName});

  final String game;
  final String gameName;

  @override
  ConsumerState<ForumThreadsTab> createState() => _ForumThreadsTabState();
}

class _ForumThreadsTabState extends ConsumerState<ForumThreadsTab> {
  String _sort = "recent";
  String? _kind;

  static const _sorts = {"recent": "Récentes", "active": "Actives", "popular": "Populaires"};
  static const _kinds = {null: "Tout", "event": "Matchs", "entity": "Équipes", "free": "Libres"};

  Future<void> _create(BuildContext context) async {
    final controller = ref.read(forumControllerProvider);
    if (!await controller.ensureCanPost(context) || !context.mounted) return;
    final title = await showDialog<String>(context: context, builder: (_) => const _NewThreadDialog());
    if (title == null || !context.mounted) return;
    try {
      final thread = await controller.createThread(title, game: widget.game);
      if (context.mounted) openThread(context, thread);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(forumEnabledProvider)) {
      return const Center(child: Text("Le forum n'est pas encore ouvert.", style: TextStyle(color: AppColors.textSecondary)));
    }
    final key = (game: widget.game, sort: _sort, kind: _kind);
    final threads = ref.watch(forumThreadsProvider(key));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(forumThreadsProvider(key));
        await ref.read(forumThreadsProvider(key).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
        children: [
          ForumEntryCard(kind: "game", targetId: widget.game, label: "Discussion générale · ${widget.gameName}"),
          FilledButton.icon(onPressed: () => _create(context), icon: const Icon(Icons.add_rounded), label: const Text("Nouvelle discussion")),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final entry in _sorts.entries) ChoiceChip(label: Text(entry.value), selected: _sort == entry.key, onSelected: (_) => setState(() => _sort = entry.key)),
            ],
          ),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final entry in _kinds.entries) ChoiceChip(label: Text(entry.value), selected: _kind == entry.key, onSelected: (_) => setState(() => _kind = entry.key)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AsyncView(
            value: threads,
            errorMessage: "Impossible de charger les discussions.",
            compactError: true,
            onRetry: () => ref.invalidate(forumThreadsProvider(key)),
            skeleton: const SkeletonCards(count: 4, height: 56, padding: EdgeInsets.zero),
            builder: (value) => value.isEmpty
                ? const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: Text("Aucune discussion pour l'instant.", style: TextStyle(color: AppColors.textSecondary))))
                : Column(children: [for (final t in value) _ThreadTile(thread: t)]),
          ),
        ],
      ),
    );
  }
}

const _kindLabels = {"event": "Match", "entity": "Équipe", "competition": "Compétition", "game": "Jeu", "free": "Discussion", "live": "Direct"};

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread});

  final ForumThreadDto thread;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(thread.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text("${_kindLabels[thread.kind.name] ?? ""} · ${_messagesLabel(thread.messageCount.toInt())}${thread.locked ? " · verrouillée" : ""}", style: const TextStyle(color: AppColors.textSecondary)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
      onTap: () => openThread(context, thread),
    );
  }
}

class _NewThreadDialog extends StatefulWidget {
  const _NewThreadDialog();

  @override
  State<_NewThreadDialog> createState() => _NewThreadDialogState();
}

class _NewThreadDialogState extends State<_NewThreadDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Nouvelle discussion"),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: "De quoi veux-tu parler ?"),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
        TextButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text("Créer")),
      ],
    );
  }
}
