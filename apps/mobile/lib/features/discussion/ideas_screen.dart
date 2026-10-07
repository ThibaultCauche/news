import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/empty_mark.dart";
import "../../widgets/page_title.dart";
import "../../widgets/section_card.dart";
import "../forum/forum_providers.dart";

const _statusLabels = {
  ForumMessageDtoIdeaStatusEnum.planned: "Prévue",
  ForumMessageDtoIdeaStatusEnum.inProgress: "En cours",
  ForumMessageDtoIdeaStatusEnum.done: "Faite",
  ForumMessageDtoIdeaStatusEnum.declined: "Refusée",
};

// Valeurs du menu (null = « Retirer le statut »).
const _setStatuses = {
  "planned": SetIdeaStatusDtoStatusEnum.planned,
  "in_progress": SetIdeaStatusDtoStatusEnum.inProgress,
  "done": SetIdeaStatusDtoStatusEnum.done,
  "declined": SetIdeaStatusDtoStatusEnum.declined,
};

const _statusIcons = {
  ForumMessageDtoIdeaStatusEnum.planned: Icons.event_outlined,
  ForumMessageDtoIdeaStatusEnum.inProgress: Icons.construction_outlined,
  ForumMessageDtoIdeaStatusEnum.done: Icons.check_circle_outline_rounded,
  ForumMessageDtoIdeaStatusEnum.declined: Icons.block_outlined,
};

/// Boîte à idées (docs/04 J24, #M9) : tout le monde propose, vote d'un 👍 ; l'équipe de l'appli pose un
/// statut (prévue, en cours, faite, refusée). Les idées encore ouvertes d'abord, les plus votées en tête.
class IdeasScreen extends ConsumerStatefulWidget {
  const IdeasScreen({super.key});

  @override
  ConsumerState<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends ConsumerState<IdeasScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _toast(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumErrorMessage(e))));
  }

  Future<void> _send(String threadId) async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final controller = ref.read(forumControllerProvider);
    if (!await controller.ensureCanPost(context) || !mounted) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      await controller.post(threadId, text);
    } catch (e) {
      _input.text = text;
      _toast(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(forumThreadProvider((kind: "feature", targetId: "ideas")));
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: switch (thread) {
          AsyncData(:final value) when value != null => _Board(threadId: value.id, input: _input, sending: _sending, onSend: () => _send(value.id)),
          AsyncData() => ErrorState(message: "La boîte à idées n'est pas disponible pour l'instant.", onRetry: () => ref.invalidate(forumThreadProvider)),
          AsyncError() => ErrorState(message: "Impossible de charger la boîte à idées.", onRetry: () => ref.invalidate(forumThreadProvider)),
          _ => const SkeletonCards(count: 4, height: 80),
        },
      ),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.threadId, required this.input, required this.sending, required this.onSend});

  final String threadId;
  final TextEditingController input;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(forumMessagesProvider(threadId));
    final status = ref.watch(forumStatusProvider).value;
    return Column(
      children: [
        Expanded(
          child: AsyncView(
            value: messages,
            errorMessage: "Impossible de charger les idées.",
            onRetry: () => ref.invalidate(forumMessagesProvider(threadId)),
            skeleton: const SkeletonCards(count: 4, height: 80),
            builder: (state) => RefreshIndicator(
              onRefresh: () => ref.read(forumMessagesProvider(threadId).notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  const PageTitle("Boîte à idées"),
                  const SizedBox(height: AppSpacing.xs),
                  const Text("Propose ce qui manque ou ce qui t'agace, vote pour les idées des autres.", style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.md),
                  if (state.messages.isEmpty) const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: EmptyMark("Aucune idée pour l'instant. Lance la première !"))),
                  for (final m in state.messages.where((m) => !m.hidden))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _IdeaCard(threadId: threadId, message: m, isModerator: status?.isModerator ?? false),
                    ),
                ],
              ),
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.surfaceBorder))),
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: "Proposer une idée…", counterText: ""),
                ),
              ),
              IconButton(tooltip: "Envoyer", onPressed: sending ? null : onSend, icon: const Icon(Icons.send_rounded)),
            ],
          ),
        ),
      ],
    );
  }
}

class _IdeaCard extends ConsumerStatefulWidget {
  const _IdeaCard({required this.threadId, required this.message, required this.isModerator});

  final String threadId;
  final ForumMessageDto message;
  final bool isModerator;

  @override
  ConsumerState<_IdeaCard> createState() => _IdeaCardState();
}

class _IdeaCardState extends ConsumerState<_IdeaCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      await action();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumErrorMessage(e))));
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final votes = m.reactions.where((r) => r.emoji == ReactionCountDtoEmojiEnum.up).fold<int>(0, (s, r) => s + r.count.toInt());
    final voted = m.myReaction == "up";
    final idea = m.ideaStatus;
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadii.chip),
            onTap: () => _run(() => ref.read(forumControllerProvider).react(widget.threadId, m, PutReactionDtoEmojiEnum.up)),
            child: Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              decoration: BoxDecoration(color: voted ? AppColors.brass.withValues(alpha: 0.16) : null, border: Border.all(color: voted ? AppColors.brass : AppColors.surfaceBorderHighlight), borderRadius: BorderRadius.circular(AppRadii.chip)),
              child: Column(
                children: [
                  Icon(Icons.arrow_drop_up_rounded, color: voted ? AppColors.brass : AppColors.textSecondary),
                  Text("$votes", style: AppTextStyles.bodyStrong),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.body ?? "", style: AppTextStyles.bodyLargeStrong),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(child: Text(m.author?.pseudo ?? "", style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label), overflow: TextOverflow.ellipsis)),
                    if (idea != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Icon(_statusIcons[idea], size: 14, color: idea == ForumMessageDtoIdeaStatusEnum.done ? AppColors.win : AppColors.textSecondary),
                      const SizedBox(width: 3),
                      Text(_statusLabels[idea] ?? "", style: TextStyle(color: idea == ForumMessageDtoIdeaStatusEnum.done ? AppColors.win : AppColors.textSecondary, fontSize: AppTypography.label, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (widget.isModerator)
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_horiz_rounded, size: 20, color: AppColors.textTertiary),
              onSelected: (value) => _run(() => ref.read(forumControllerProvider).setIdeaStatus(widget.threadId, m.id, _setStatuses[value])),
              itemBuilder: (_) => [
                const PopupMenuItem(value: "planned", child: Text("Marquer prévue")),
                const PopupMenuItem(value: "in_progress", child: Text("Marquer en cours")),
                const PopupMenuItem(value: "done", child: Text("Marquer faite")),
                const PopupMenuItem(value: "declined", child: Text("Marquer refusée")),
                if (idea != null) const PopupMenuItem(value: "none", child: Text("Retirer le statut")),
              ],
            ),
        ],
      ),
    );
  }
}
