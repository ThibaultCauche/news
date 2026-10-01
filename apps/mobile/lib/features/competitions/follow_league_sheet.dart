import "../../theme/app_theme.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../theme/tokens.dart";
import "../../widgets/follow_button.dart";
import "../follows/follows_provider.dart";

/// Bouton « Suivre » d'une page de ligue (docs/04 J10) : il ouvre le choix de ce qu'on
/// suit (toute la ligue, ou certaines compétitions sans l'année). « Suivi » dès qu'on suit
/// la ligue ou l'une de ses familles.
class LeagueFollowButton extends ConsumerWidget {
  const LeagueFollowButton({super.key, required this.league});

  final CatalogLeagueDto league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final follows = ref.watch(followsProvider).value;
    final following = isFollowing(follows, FollowTargetType.competition, league.id) ||
        league.families.any((f) => isFollowing(follows, FollowTargetType.competitionFamily, f.id));
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: Center(child: FollowButton(following: following, onPressed: () => showFollowLeagueSheet(context, league: league))),
    );
  }
}

Future<void> showFollowLeagueSheet(BuildContext context, {required CatalogLeagueDto league}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FollowLeagueSheet(league: league),
  );
}

/// Une case par compétition qui revient d'année en année (« Champions », « Masters »…),
/// plus « Toute la ligue ». « Valider » suit directement, et retire ce qui est décoché :
/// c'est aussi ici qu'on se désabonne d'une ligue.
class FollowLeagueSheet extends ConsumerStatefulWidget {
  const FollowLeagueSheet({super.key, required this.league});

  final CatalogLeagueDto league;

  @override
  ConsumerState<FollowLeagueSheet> createState() => _FollowLeagueSheetState();
}

class _FollowLeagueSheetState extends ConsumerState<FollowLeagueSheet> {
  late bool _all;
  late final Set<String> _families;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final follows = ref.read(followsProvider).value;
    _all = isFollowing(follows, FollowTargetType.competition, widget.league.id);
    _families = {
      for (final f in widget.league.families)
        if (isFollowing(follows, FollowTargetType.competitionFamily, f.id)) f.id,
    };
  }

  Future<void> _validate() async {
    final league = widget.league;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final controller = ref.read(followsControllerProvider);
    final follows = ref.read(followsProvider).value;
    setState(() => _saving = true);
    try {
      final wasAll = isFollowing(follows, FollowTargetType.competition, league.id);
      if (_all && !wasAll) await controller.follow(FollowTargetType.competition, league.id, name: league.name);
      if (!_all && wasAll) await controller.unfollow(FollowTargetType.competition, league.id);

      // Suivre toute la ligue rend les familles redondantes : on les retire.
      final wanted = _all ? const <String>{} : _families;
      for (final family in league.families) {
        final was = isFollowing(follows, FollowTargetType.competitionFamily, family.id);
        final want = wanted.contains(family.id);
        if (want && !was) await controller.follow(FollowTargetType.competitionFamily, family.id, name: family.name);
        if (!want && was) await controller.unfollow(FollowTargetType.competitionFamily, family.id);
      }

      // Une sourdine n'a de sens que sous un suivi : on retire celles des séries qui ne sont
      // plus couvertes, sinon elles referaient surface à un prochain suivi.
      for (final serie in league.children) {
        final covered = _all || (serie.familyId != null && _families.contains(serie.familyId));
        if (!covered && isMuted(follows, FollowTargetType.competition, serie.id)) {
          await controller.unfollow(FollowTargetType.competition, serie.id);
        }
      }
      navigator.pop();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Impossible de modifier ce suivi.")));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Suivre dans ${league.name}", style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              "Les nouvelles éditions sont incluses automatiquement.",
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _all,
              onChanged: (v) => setState(() => _all = v ?? false),
              title: Text("Toute la ligue ${league.name}", style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text("Toutes ses compétitions, actuelles et futures"),
            ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final family in league.families)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _all || _families.contains(family.id),
                      // Cochée d'office quand toute la ligue est suivie.
                      onChanged: _all ? null : (v) => setState(() => v == true ? _families.add(family.id) : _families.remove(family.id)),
                      title: Text(family.name),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _saving ? null : _validate, child: const Text("Valider")),
            ),
          ],
        ),
      ),
    );
  }
}
