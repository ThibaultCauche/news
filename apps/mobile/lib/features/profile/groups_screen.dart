import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:share_plus/share_plus.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/auth/account.dart";
import "../../core/settings_provider.dart";
import "../../theme/app_theme.dart";
import "../../widgets/avatar_circle.dart";
import "../../theme/tokens.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../competitions/competitions_data.dart";
import "../predictions/predictions_screen.dart";
import "community_providers.dart";
import "player_profile_screen.dart";

/// Groupes d'amis (docs/04 J11) : liste, créer, rejoindre par code (8 caractères).
class GroupsSection extends ConsumerWidget {
  const GroupsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider).value ?? const <GroupDto>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("GROUPES D'AMIS"),
        const SizedBox(height: AppSpacing.sm),
        if (groups.isEmpty)
          const Text("Crée un groupe ou rejoins celui d'un ami avec son code pour comparer vos pronostics.", style: TextStyle(color: AppColors.textSecondary)),
        for (final group in groups) ...[
          SectionCard(
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupScreen(groupId: group.id))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.name, style: AppTextStyles.bodyLargeStrong),
                        Text("${group.memberCount} membre${group.memberCount > 1 ? "s" : ""}", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: () => _prompt(context, ref, create: true), child: const Text("Créer un groupe"))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: OutlinedButton(onPressed: () => _prompt(context, ref, create: false), child: const Text("Rejoindre"))),
          ],
        ),
      ],
    );
  }

  Future<void> _prompt(BuildContext context, WidgetRef ref, {required bool create}) {
    return showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _GroupPrompt(create: create));
  }
}

class _GroupPrompt extends ConsumerStatefulWidget {
  const _GroupPrompt({required this.create});

  final bool create;

  @override
  ConsumerState<_GroupPrompt> createState() => _GroupPromptState();
}

class _GroupPromptState extends ConsumerState<_GroupPrompt> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final community = ref.read(communityControllerProvider);
    try {
      final group = widget.create ? await community.createGroup(_controller.text.trim()) : await community.joinGroup(_controller.text);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      navigator.push(MaterialPageRoute(builder: (_) => GroupScreen(groupId: group.id)));
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e) ?? accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.create ? "Créer un groupe" : "Rejoindre un groupe", style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: widget.create ? 40 : 8,
            textCapitalization: widget.create ? TextCapitalization.sentences : TextCapitalization.characters,
            decoration: InputDecoration(labelText: widget.create ? "Nom du groupe" : "Code d'invitation"),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.live)),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.create ? "Créer" : "Rejoindre"),
            ),
          ),
        ],
      ),
    );
  }
}

/// Classement d'un groupe. Les points dévoilent des résultats : sans spoil, masqués jusqu'à un appui long.
class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  bool _revealed = false;
  // Filtre du classement (J14) : `null` = tous les jeux.
  String? _game;

  Future<void> _leaveOrDelete(GroupDetailDto group) async {
    final community = ref.read(communityControllerProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(group.isOwner ? "Supprimer le groupe ?" : "Quitter le groupe ?"),
        content: Text(group.isOwner ? "Le groupe et son classement disparaissent pour tous ses membres." : "Tu pourras le rejoindre à nouveau avec son code."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(group.isOwner ? "Supprimer" : "Quitter")),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await (group.isOwner ? community.deleteGroup(group.id) : community.leaveGroup(group.id));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e) ?? accountErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(groupDetailProvider((id: widget.groupId, game: _game)));
    final hidden = (ref.watch(userSettingProvider).value?.spoilerFree ?? true) && !_revealed;
    return Scaffold(
      appBar: AppBar(
        actions: [
          // Le code d'invitation n'est pas affiché en permanence : il apparaît derrière l'icône.
          if (detail.value != null)
            IconButton(tooltip: "Inviter", icon: const Icon(Icons.person_add_alt_1_outlined), onPressed: () => _showInvite(detail.value!)),
        ],
      ),
      body: switch (detail) {
        AsyncData(:final value) => _body(context, value, hidden),
        AsyncError() => const Center(child: Text("Impossible de charger ce groupe.")),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  void _showInvite(GroupDetailDto group) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Inviter des amis", style: AppTextStyles.sectionTitle),
              const SizedBox(height: AppSpacing.xs),
              const Text("Ils saisissent ce code dans « Rejoindre ».", style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(child: Text(group.code, style: AppTextStyles.heroScore)),
                  IconButton(
                    tooltip: "Partager",
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => SharePlus.instance.share(ShareParams(text: "Rejoins mon groupe « ${group.name} » sur News pour comparer nos pronostics. Code d'invitation : ${group.code}")),
                  ),
                  IconButton(
                    tooltip: "Copier le code",
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: group.code));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text("Code copié")));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, GroupDetailDto group, bool hidden) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(group.name, style: AppTextStyles.pageTitle),
        const SizedBox(height: AppSpacing.md),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel("CLASSEMENT"),
        const SizedBox(height: AppSpacing.sm),
        _GameChips(selected: _game, onSelected: (slug) => setState(() => _game = slug)),
        GestureDetector(
          onLongPress: hidden ? () => setState(() => _revealed = true) : null,
          child: SectionCard(
            child: Column(
              children: [
                for (final entry in group.ranking)
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfileScreen(userId: entry.userId))),
                    child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        SizedBox(width: 28, child: Text(hidden ? "" : "${entry.rank}", style: const TextStyle(color: AppColors.textSecondary))),
                        AvatarCircle(avatarUrl: entry.avatarUrl, pseudo: entry.pseudo, radius: 14),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(entry.pseudo, style: entry.isMe ? AppTextStyles.bodyLargeStrong.copyWith(color: AppColors.gold) : AppTextStyles.bodyLargeStrong)),
                        Text(hidden ? "•••" : "${entry.points} pts", style: AppTextStyles.bodyStrong),
                      ],
                    ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (hidden) const Padding(padding: EdgeInsets.only(top: AppSpacing.sm), child: Text("Sans spoil : appui long pour afficher le classement.", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption))),
        const SizedBox(height: AppSpacing.lg),
        TextButton(
          onPressed: () => _leaveOrDelete(group),
          child: Text(group.isOwner ? "Supprimer le groupe" : "Quitter le groupe", style: const TextStyle(color: AppColors.live)),
        ),
      ],
    );
  }
}

/// Puces « Tous / jeu » du classement, comme sur l'écran Pronostics ; rien à choisir avec un seul jeu.
class _GameChips extends ConsumerWidget {
  const _GameChips({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = catalogGames(ref.watch(catalogProvider).value);
    if (games.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            ChoiceChip(label: const Text("Tous"), selected: selected == null, onSelected: (_) => onSelected(null)),
            for (final game in games) ...[
              const SizedBox(width: AppSpacing.sm),
              ChoiceChip(label: Text(game.name), selected: selected == game.slug, onSelected: (_) => onSelected(game.slug)),
            ],
          ],
        ),
      ),
    );
  }
}
