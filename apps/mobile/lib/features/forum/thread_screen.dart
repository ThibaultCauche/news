import "../../widgets/ornate_frame.dart";
import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/avatar_circle.dart";
import "../../widgets/spoiler_hold.dart";
import "../profile/player_profile_screen.dart";
import "forum_providers.dart";

/// Fil de discussion (docs/04 J13) : messages texte seul, réponses, réactions, signalement,
/// blocage. Les plus récents en haut ; rechargé toutes les 30 s tant que l'écran est ouvert.
/// Avec le sans spoil, le fil est flouté et un appui long le révèle (comme le score d'un match).
class ForumThreadScreen extends ConsumerStatefulWidget {
  const ForumThreadScreen({super.key, required this.threadId, this.title});

  final String threadId;
  final String? title;

  @override
  ConsumerState<ForumThreadScreen> createState() => _ForumThreadScreenState();
}

class _ForumThreadScreenState extends ConsumerState<ForumThreadScreen> {
  // 5 s : le tchat du direct se recharge à ce rythme, les autres fils une fois sur six (30 s).
  static const _pollInterval = Duration(seconds: 5);

  final _input = TextEditingController();
  Timer? _timer;
  ForumMessageDto? _replyTo;
  bool _revealed = false;
  // Messages dont les réponses sont repliées (appui long, comme sur Reddit).
  final _collapsed = <String>{};
  bool _sending = false;
  int _tick = 0;
  ForumMessageDto? _editing;
  bool _spoiler = false;
  // Spoilers annoncés par leur auteur que l'utilisateur a choisi d'afficher.
  final _revealedSpoilers = <String>{};

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _poll() {
    _tick++;
    final live = ref.read(forumMessagesProvider(widget.threadId)).value?.thread.kind == ForumThreadDtoKindEnum.live;
    if (live || _tick % 6 == 0) _refresh();
  }

  void _startEdit(ForumMessageDto message) {
    setState(() {
      _editing = message;
      _replyTo = null;
      _input.text = message.body ?? "";
    });
  }

  Future<void> _refresh() async {
    try {
      await ref.read(forumMessagesProvider(widget.threadId).notifier).refresh();
    } catch (_) {
      // Hors ligne ou erreur passagère : on garde ce qui est affiché.
    }
  }

  void _toast(Object error) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumErrorMessage(error))));
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final controller = ref.read(forumControllerProvider);
      if (_editing != null) {
        await controller.editMessage(widget.threadId, _editing!.id, text);
      } else {
        await controller.post(widget.threadId, text, parentId: _replyTo?.id, isSpoiler: _spoiler);
      }
      _input.clear();
      setState(() {
        _replyTo = null;
        _editing = null;
        _spoiler = false;
      });
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(forumMessagesProvider(widget.threadId));
    final status = ref.watch(forumStatusProvider).value;
    final spoilerFree = ref.watch(userSettingProvider).value?.spoilerFree ?? false;
    final thread = messages.value?.thread;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Discussion"),
        actions: [
          if (thread != null)
            IconButton(
              tooltip: thread.following ? "Ne plus suivre cette discussion" : "Suivre cette discussion",
              icon: Icon(thread.following ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
              onPressed: () => ref.read(forumControllerProvider).setFollow(widget.threadId, !thread.following).catchError(_toast),
            ),
          if (status?.isModerator == true && thread != null)
            PopupMenuButton<bool>(
              onSelected: (lock) async {
                try {
                  await ref.read(forumControllerProvider).setLock(thread.id, locked: lock);
                  await _refresh();
                } catch (e) {
                  _toast(e);
                }
              },
              itemBuilder: (_) => [
                if (thread.locked) const PopupMenuItem(value: false, child: Text("Déverrouiller la discussion")) else const PopupMenuItem(value: true, child: Text("Verrouiller la discussion")),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: switch (messages) {
                AsyncData(:final value) => _list(context, value, status, spoilerFree && !_revealed),
                AsyncError() when !messages.hasValue => const Center(child: Text("Impossible de charger la discussion.")),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
            _Composer(
              controller: _input,
              locked: thread?.locked ?? false,
              canPost: status?.canPost ?? false,
              replyTo: _replyTo,
              sending: _sending,
              onCancelReply: () => setState(() => _replyTo = null),
              onSend: _send,
              onNeedAccess: () => ref.read(forumControllerProvider).ensureCanPost(context),
              readOnly: thread?.readOnly ?? false,
              liveChat: thread?.kind == ForumThreadDtoKindEnum.live,
              editing: _editing,
              spoiler: _spoiler,
              onToggleSpoiler: () => setState(() => _spoiler = !_spoiler),
              onCancelEdit: () => setState(() {
                _editing = null;
                _input.clear();
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleCollapse(String id) => setState(() => _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id));

  /// Tchat du direct : du plus ancien au plus récent, le plus récent en bas (liste inversée, donc
  /// elle reste collée en bas quand un message arrive). Pas de pull-to-refresh : le rechargement est
  /// automatique toutes les 5 secondes.
  Widget _liveListView(ForumMessagesState state, ForumStatusDto? status) {
    final canReply = !(state.thread.locked || state.thread.readOnly);
    final more = state.nextBefore != null;
    final empty = state.messages.isEmpty;
    // Index 0 = message le plus récent (en bas) ; en dernier : « plus anciens » puis le titre, en haut.
    final count = (empty ? 1 : state.messages.length) + (more ? 1 : 0) + 1;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      itemCount: count,
      itemBuilder: (context, i) {
        if (i == count - 1) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(state.thread.title, style: Theme.of(context).textTheme.titleMedium),
          );
        }
        if (empty) {
          return const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: Text("Le tchat démarre : écris le premier message !", style: TextStyle(color: AppColors.textSecondary))));
        }
        if (more && i == state.messages.length) {
          return TextButton(
            onPressed: () => ref.read(forumMessagesProvider(widget.threadId).notifier).loadMore().catchError(_toast),
            child: const Text("Voir les messages plus anciens"),
          );
        }
        return _LiveMessageRow(
          message: state.messages[i],
          canReply: canReply,
          onReply: (m) => setState(() {
            _replyTo = m;
            _editing = null;
          }),
          onActions: (m) => _liveActions(m, status),
        );
      },
    );
  }

  Future<void> _liveActions(ForumMessageDto message, ForumStatusDto? status) async {
    final author = message.author;
    if (author == null) return;
    final mine = author.userId == status?.userId;
    final isModerator = status?.isModerator ?? false;
    final controller = ref.read(forumControllerProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine) ListTile(leading: const Icon(Icons.flag_outlined), title: const Text("Signaler"), onTap: () => Navigator.pop(sheet, "report")),
            if (!mine) ListTile(leading: const Icon(Icons.block_outlined), title: Text("Bloquer ${author.pseudo}"), onTap: () => Navigator.pop(sheet, "block")),
            if (mine) ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text("Supprimer"), onTap: () => Navigator.pop(sheet, "delete")),
            if (isModerator && !mine) ListTile(leading: const Icon(Icons.shield_outlined), title: const Text("Masquer (modération)"), onTap: () => Navigator.pop(sheet, "hide")),
            if (isModerator && !mine) ListTile(leading: const Icon(Icons.gavel_outlined), title: const Text("Exclure du forum"), onTap: () => Navigator.pop(sheet, "ban")),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case "report":
          final reason = await _pickReportReason(context);
          if (reason == null || !mounted) return;
          await controller.report(widget.threadId, message.id, reason);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Merci, le message a été signalé.")));
        case "block":
          await controller.block(widget.threadId, author.userId);
        case "delete":
          await controller.deleteMessage(widget.threadId, message.id);
        case "hide":
          await controller.hideMessage(message.id);
          await _refresh();
        case "ban":
          await controller.setBan(author.userId, banned: true);
      }
    } catch (e) {
      _toast(e);
    }
  }

  Widget _list(BuildContext context, ForumMessagesState state, ForumStatusDto? status, bool blurred) {
    // Le titre complet est en tête de la liste (la barre est trop étroite pour un titre de 80 caractères).
    final header = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(state.thread.title, style: Theme.of(context).textTheme.titleLarge),
    );
    final list = state.thread.kind == ForumThreadDtoKindEnum.live
        ? _liveListView(state, status)
        : RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: 1 + (state.messages.isEmpty ? 1 : state.messages.length) + (state.nextBefore != null ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == 0) return header;
          if (state.messages.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: Text("Aucun message pour l'instant. Lance la discussion !", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary))),
            );
          }
          if (i == state.messages.length + 1) {
            return TextButton(
              onPressed: () => ref.read(forumMessagesProvider(widget.threadId).notifier).loadMore().catchError(_toast),
              child: const Text("Voir les messages plus anciens"),
            );
          }
          return _MessageTile(
            threadId: widget.threadId,
            message: state.messages[i - 1],
            status: status,
            collapsed: _collapsed,
            canCollapse: !blurred,
            onToggleCollapse: _toggleCollapse,
            onReply: (m) => setState(() {
              _replyTo = m;
              _editing = null;
            }),
            canReply: !(state.thread.locked || state.thread.readOnly),
            revealedSpoilers: _revealedSpoilers,
            onRevealSpoiler: (id) => setState(() => _revealedSpoilers.add(id)),
            onEdit: _startEdit,
          );
        },
      ),
    );
    if (!blurred || state.messages.isEmpty) return list;
    return SpoilerHold(
      onReveal: () => setState(() => _revealed = true),
      builder: (context, sigma) => Stack(
        children: [
          SpoilerBlur(sigma: sigma, child: list),
          if (sigma > 0)
            const Positioned(
              top: AppSpacing.md,
              left: AppSpacing.md,
              right: AppSpacing.md,
              child: IgnorePointer(
                child: FramedCard(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Text("Sans spoil : discussion floutée. Appui long pour l'afficher.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final _mention = RegExp(r"@[\p{L}\p{N}_.-]{3,20}", unicode: true);

TextSpan _mentionSpan(String body) {
  final spans = <TextSpan>[];
  var last = 0;
  for (final m in _mention.allMatches(body)) {
    if (m.start > last) spans.add(TextSpan(text: body.substring(last, m.start)));
    spans.add(TextSpan(text: m.group(0), style: const TextStyle(fontWeight: FontWeight.w700)));
    last = m.end;
  }
  if (last < body.length) spans.add(TextSpan(text: body.substring(last)));
  return TextSpan(children: spans);
}

/// Raisons de signalement proposées (fils classiques et tchat du direct).
const _reportLabels = {
  ReportMessageDtoReasonEnum.insult: "Insulte ou propos haineux",
  ReportMessageDtoReasonEnum.spam: "Spam ou publicité",
  ReportMessageDtoReasonEnum.spoiler: "Spoiler non annoncé",
  ReportMessageDtoReasonEnum.other: "Autre",
};

Future<ReportMessageDtoReasonEnum?> _pickReportReason(BuildContext context) {
  return showModalBottomSheet<ReportMessageDtoReasonEnum>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in _reportLabels.entries) ListTile(title: Text(entry.value), onTap: () => Navigator.pop(context, entry.key)),
        ],
      ),
    ),
  );
}

/// Une ligne du tchat du direct : avatar, pseudo et texte, rien d'autre. Un tap répond (cite le
/// message, pas de fil) ; l'appui long ouvre signaler, bloquer, supprimer et la modération.
class _LiveMessageRow extends StatelessWidget {
  const _LiveMessageRow({required this.message, required this.canReply, required this.onReply, required this.onActions});

  final ForumMessageDto message;
  final bool canReply;
  final ValueChanged<ForumMessageDto> onReply;
  final ValueChanged<ForumMessageDto> onActions;

  @override
  Widget build(BuildContext context) {
    final author = message.author;
    final quoted = message.replyTo;
    return InkWell(
      onTap: canReply ? () => onReply(message) : null,
      onLongPress: () {
        HapticFeedback.selectionClick();
        onActions(message);
      },
      child: Padding(
        padding: EdgeInsets.only(top: quoted == null ? 3 : 8, bottom: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (quoted != null)
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  "↪ ${quoted.pseudo ?? "…"} : ${quoted.snippet}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: AvatarCircle(avatarUrl: author?.avatarUrl, pseudo: author?.pseudo, radius: 10)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: "${author?.pseudo ?? ""}  ", style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                        _mentionSpan(message.body ?? ""),
                      ],
                    ),
                    style: const TextStyle(height: 1.3, fontSize: AppTypography.body),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _emojiByName = {"up": "👍", "fire": "🔥", "laugh": "😂", "wow": "😮", "sad": "😢"};
const _reactionOrder = [PutReactionDtoEmojiEnum.up, PutReactionDtoEmojiEnum.fire, PutReactionDtoEmojiEnum.laugh, PutReactionDtoEmojiEnum.wow, PutReactionDtoEmojiEnum.sad];

String _ago(DateTime date) {
  final d = DateTime.now().difference(date.toLocal());
  if (d.inMinutes < 1) return "à l'instant";
  if (d.inMinutes < 60) return "il y a ${d.inMinutes} min";
  if (d.inHours < 24) return "il y a ${d.inHours} h";
  return "il y a ${d.inDays} j";
}

int _descendants(ForumMessageDto m) => m.replies.fold(0, (sum, r) => sum + 1 + _descendants(r));

class _MessageTile extends ConsumerWidget {
  const _MessageTile({
    required this.threadId,
    required this.message,
    required this.status,
    required this.collapsed,
    required this.canCollapse,
    required this.onToggleCollapse,
    required this.onReply,
    required this.canReply,
    required this.revealedSpoilers,
    required this.onRevealSpoiler,
    required this.onEdit,
    this.depth = 0,
  });

  final String threadId;
  final ForumMessageDto message;
  final ForumStatusDto? status;
  final Set<String> collapsed;
  final bool canCollapse;
  final ValueChanged<String> onToggleCollapse;
  final ValueChanged<ForumMessageDto> onReply;
  final bool canReply;
  final Set<String> revealedSpoilers;
  final ValueChanged<String> onRevealSpoiler;
  final ValueChanged<ForumMessageDto> onEdit;
  final int depth;

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumErrorMessage(e))));
    }
  }

  Future<void> _pickReaction(BuildContext context, WidgetRef ref) async {
    final emoji = await showModalBottomSheet<PutReactionDtoEmojiEnum>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final e in _reactionOrder)
                IconButton(onPressed: () => Navigator.pop(context, e), iconSize: 30, icon: Text(_emojiByName[e.name]!)),
            ],
          ),
        ),
      ),
    );
    if (emoji != null && context.mounted) await _run(context, () => ref.read(forumControllerProvider).react(threadId, message, emoji));
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final reason = await _pickReportReason(context);
    if (reason == null || !context.mounted) return;
    await _run(context, () async {
      await ref.read(forumControllerProvider).report(threadId, message.id, reason);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Merci, le message a été signalé.")));
    });
  }

  /// Texte du message : mentions @pseudo en gras ; un spoiler annoncé reste flouté jusqu'au tap.
  Widget _body() {
    final text = Text.rich(_mentionSpan(message.body ?? ""), style: const TextStyle(height: 1.3));
    if (!message.isSpoiler || revealedSpoilers.contains(message.id)) return text;
    return GestureDetector(
      onTap: () => onRevealSpoiler(message.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpoilerBlur(sigma: 7, child: text),
          const Text("Spoiler · touche pour afficher", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label)),
        ],
      ),
    );
  }

  void _openProfile(BuildContext context, ForumAuthorDto author) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfileScreen(userId: author.userId)));
  }

  /// Réponses : sous le message, derrière un repère vertical (comme Reddit) qui montre à qui on
  /// répond ; repliées, un bouton « Voir les N réponses » les remplace.
  Widget _replies(BuildContext context) {
    if (message.replies.isEmpty) return const SizedBox.shrink();
    if (collapsed.contains(message.id)) {
      final count = _descendants(message);
      return TextButton(
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm), minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        onPressed: () => onToggleCollapse(message.id),
        child: Text(count == 1 ? "Voir la réponse" : "Voir les $count réponses"),
      );
    }
    return Container(
      margin: const EdgeInsets.only(left: 8, top: AppSpacing.xs),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.18), width: 2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final reply in message.replies)
            _MessageTile(
              threadId: threadId,
              message: reply,
              status: status,
              collapsed: collapsed,
              canCollapse: canCollapse,
              onToggleCollapse: onToggleCollapse,
              onReply: onReply,
              canReply: canReply,
              revealedSpoilers: revealedSpoilers,
              onRevealSpoiler: onRevealSpoiler,
              onEdit: onEdit,
              depth: depth + 1,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(forumControllerProvider);
    final author = message.author;
    final mine = author != null && author.userId == status?.userId;
    final isModerator = status?.isModerator ?? false;
    final radius = depth == 0 ? 16.0 : 12.0;

    if (message.hidden) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Message masqué", style: TextStyle(color: AppColors.textTertiary, fontStyle: FontStyle.italic)),
            _replies(context),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Appui long : plie ou déplie les réponses (rien à plier sans réponse).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: canCollapse && message.replies.isNotEmpty
                ? () {
                    HapticFeedback.selectionClick();
                    onToggleCollapse(message.id);
                  }
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: author == null ? null : () => _openProfile(context, author),
                  child: AvatarCircle(avatarUrl: author?.avatarUrl, pseudo: author?.pseudo, radius: radius),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (message.pinned)
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.push_pin_outlined, size: 13, color: AppColors.textSecondary),
                                SizedBox(width: 2),
                                Text("Épinglé", style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.label)),
                              ],
                            ),
                          InkWell(
                            onTap: author == null ? null : () => _openProfile(context, author),
                            child: Text(author?.pseudo ?? "", style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          if (author?.camp != null) _CampBadge(camp: author!.camp!),
                          Text(message.edited ? "${_ago(message.createdAt)} · modifié" : _ago(message.createdAt), style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.label)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      _body(),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz_rounded, size: 20, color: AppColors.textTertiary),
                  onSelected: (value) => switch (value) {
                    "report" => _report(context, ref),
                    "edit" => Future.sync(() => onEdit(message)),
                    "pin" => _run(context, () => controller.setPin(threadId, message.id, !message.pinned)),
                    "block" => _run(context, () => controller.block(threadId, author!.userId)),
                    "delete" => _run(context, () => controller.deleteMessage(threadId, message.id)),
                    "hide" => _run(context, () async {
                      await controller.hideMessage(message.id);
                      await ref.read(forumMessagesProvider(threadId).notifier).refresh();
                    }),
                    "ban" => _run(context, () => controller.setBan(author!.userId, banned: true)),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    if (!mine) const PopupMenuItem(value: "report", child: Text("Signaler")),
                    if (!mine) PopupMenuItem(value: "block", child: Text("Bloquer ${author?.pseudo ?? ""}")),
                    if (mine && DateTime.now().difference(message.createdAt.toLocal()).inMinutes < 5) const PopupMenuItem(value: "edit", child: Text("Modifier")),
                    if (mine) const PopupMenuItem(value: "delete", child: Text("Supprimer")),
                    if (isModerator && depth == 0) PopupMenuItem(value: "pin", child: Text(message.pinned ? "Désépingler" : "Épingler")),
                    if (isModerator && !mine) const PopupMenuItem(value: "hide", child: Text("Masquer (modération)")),
                    if (isModerator && !mine) const PopupMenuItem(value: "ban", child: Text("Exclure du forum")),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: radius * 2 + AppSpacing.sm, top: AppSpacing.xs),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final r in message.reactions)
                  _ReactionChip(
                    emoji: _emojiByName[r.emoji.name] ?? "",
                    count: r.count.toInt(),
                    mine: message.myReaction == r.emoji.name,
                    onTap: () => _run(context, () => controller.react(threadId, message, PutReactionDtoEmojiEnum.valueOf(r.emoji.name))),
                  ),
                InkWell(
                  onTap: () => _pickReaction(context, ref),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.add_reaction_outlined, size: 18, color: AppColors.textTertiary)),
                ),
                TextButton(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm), minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: canReply ? () => onReply(message) : null,
                  child: const Text("Répondre", style: TextStyle(fontSize: AppTypography.caption)),
                ),
              ],
            ),
          ),
          _replies(context),
        ],
      ),
    );
  }
}

/// Badge de camp : petit logo et nom de l'équipe suivie par l'auteur pour le jeu du fil. L'or
/// est réservé à « mon équipe » (règle 12) : le badge reste neutre.
class _CampBadge extends StatelessWidget {
  const _CampBadge({required this.camp});

  final ForumCampBadgeDto camp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.pill), border: Border.all(color: AppColors.surfaceBorderHighlight)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (camp.imageUrl != null) ...[
            Container(
              width: 14,
              height: 14,
              padding: const EdgeInsets.all(1.5),
              decoration: const BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle),
              child: Image.network(camp.imageUrl!, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
            const SizedBox(width: 4),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(camp.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppTypography.label, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.emoji, required this.count, required this.mine, required this.onTap});

  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: mine ? AppColors.surfaceHighlight : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: mine ? AppColors.textSecondary : AppColors.surfaceBorderHighlight),
        ),
        child: Text("$emoji $count", style: const TextStyle(fontSize: AppTypography.caption)),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.locked,
    required this.canPost,
    required this.replyTo,
    required this.sending,
    required this.onCancelReply,
    required this.onSend,
    required this.onNeedAccess,
    required this.readOnly,
    required this.liveChat,
    required this.editing,
    required this.spoiler,
    required this.onToggleSpoiler,
    required this.onCancelEdit,
  });

  final TextEditingController controller;
  final bool locked;
  final bool canPost;
  final ForumMessageDto? replyTo;
  final bool sending;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;
  final Future<bool> Function() onNeedAccess;
  final bool readOnly;
  final bool liveChat;
  final ForumMessageDto? editing;
  final bool spoiler;
  final VoidCallback onToggleSpoiler;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    if (locked) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Text("Cette discussion est verrouillée.", style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    if (readOnly) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Text("Le direct n'est ouvert que pendant le match.", style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.surfaceBorder))),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyTo != null)
            Row(
              children: [
                Expanded(child: Text("Réponse à ${replyTo!.author?.pseudo ?? "un message"}", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption))),
                IconButton(onPressed: onCancelReply, icon: const Icon(Icons.close_rounded, size: 18), visualDensity: VisualDensity.compact),
              ],
            ),
          if (editing != null)
            Row(
              children: [
                const Expanded(child: Text("Modification du message", style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption))),
                IconButton(onPressed: onCancelEdit, icon: const Icon(Icons.close_rounded, size: 18), visualDensity: VisualDensity.compact),
              ],
            ),
          if (canPost && editing == null && !liveChat)
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text("Spoiler"),
                selected: spoiler,
                onSelected: (_) => onToggleSpoiler(),
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (!canPost)
            // Invité, pseudo manquant, conditions non acceptées… : on déroule les étapes au tap.
            InkWell(
              onTap: onNeedAccess,
              borderRadius: BorderRadius.circular(AppRadii.chip),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.chip)),
                child: const Text("Écrire un message…", style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: "Écrire un message…", counterText: ""),
                  ),
                ),
                IconButton(
                  tooltip: "Envoyer",
                  onPressed: sending ? null : onSend,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
