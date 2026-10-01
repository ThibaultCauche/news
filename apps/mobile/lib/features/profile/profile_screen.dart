import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/auth/account.dart";
import "../../core/settings_provider.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/avatar_circle.dart";
import "../../widgets/page_title.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../account/auth_screen.dart";
import "../follows/follows_screen.dart";
import "../learn/learn_screen.dart";
import "../forum/forum_account_screens.dart";
import "../settings/settings_screen.dart";
import "../competitions/competitions_data.dart";
import "../predictions/predictions_screen.dart";
import "community_providers.dart";

/// Écran Profil (docs/04 J11), ouvert depuis l'avatar de l'Accueil : compte, pseudo, stats de
/// pronostics, groupes d'amis, accès aux suivis ; les réglages s'ouvrent par le rouage en haut à
/// droite. Optionnel : l'invité y trouve seulement l'invitation à créer un compte.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(signedInProvider);
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: "Réglages",
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(profileProvider);
          ref.invalidate(groupsProvider);
          await ref.read(profileProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const PageTitle("Profil"),
            const SizedBox(height: AppSpacing.md),
            if (!signedIn) const _GuestCard() else const _AccountSections(),
            const SizedBox(height: AppSpacing.lg),
            if (signedIn) ...[
              SectionCard(
                child: _NavRow(
                  icon: Icons.star_outline_rounded,
                  label: "Mes suivis",
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FollowsScreen())),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const _LearnRow(),
              const SizedBox(height: AppSpacing.lg),
              const ForumProfileSection(),
              const _AccountActions(),
            ],
            const SizedBox(height: AppSpacing.xl * 2),
          ],
        ),
      ),
      ),
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Tu navigues en invité", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            "Crée un compte pour suivre des équipes, recevoir des alertes, pronostiquer les matchs et te comparer à tes amis.",
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen())),
              child: const Text("Créer un compte"),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(signUp: false))),
              child: const Text("J'ai déjà un compte"),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSections extends ConsumerWidget {
  const _AccountSections();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return switch (profile) {
      AsyncData(:final value) when value != null => _profile(context, ref, value),
      AsyncError() when profile.hasValue && profile.value != null => _profile(context, ref, profile.value!),
      AsyncError() => const Text("Impossible de charger ton profil.", style: TextStyle(color: AppColors.textSecondary)),
      _ => const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: CircularProgressIndicator())),
    };
  }

  Widget _profile(BuildContext context, WidgetRef ref, ProfileDto profile) {
    if (!profile.emailVerified) return const _VerifyEmailCard();
    if (profile.pseudo == null) return const _PseudoForm(first: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PseudoHeader(profile: profile),
        const SizedBox(height: AppSpacing.md),
        StatsCard(stats: profile.stats),
      ],
    );
  }
}

/// E-mail pas encore vérifié : Firebase a envoyé un lien, on attend le clic.
class _VerifyEmailCard extends ConsumerStatefulWidget {
  const _VerifyEmailCard();

  @override
  ConsumerState<_VerifyEmailCard> createState() => _VerifyEmailCardState();
}

class _VerifyEmailCardState extends ConsumerState<_VerifyEmailCard> {
  String? _message;

  Future<void> _check() async {
    try {
      final verified = await ref.read(accountServiceProvider).refreshVerification();
      if (!mounted) return;
      if (verified) {
        ref.invalidate(profileProvider);
      } else {
        setState(() => _message = "Pas encore vérifié. Ouvre le lien reçu par e-mail, puis reviens ici.");
      }
    } catch (e) {
      if (mounted) setState(() => _message = accountErrorMessage(e));
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(accountServiceProvider).resendVerification();
      if (mounted) setState(() => _message = "E-mail renvoyé.");
    } catch (e) {
      if (mounted) setState(() => _message = accountErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.read(accountServiceProvider).email ?? "ton adresse";
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Vérifie ton e-mail", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text("Un lien de confirmation a été envoyé à $email. Il faut le valider pour créer ton pseudo et jouer.", style: const TextStyle(color: AppColors.textSecondary)),
          if (_message != null) ...[const SizedBox(height: AppSpacing.sm), Text(_message!, style: const TextStyle(color: AppColors.textSecondary))],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              FilledButton(onPressed: _check, child: const Text("J'ai vérifié")),
              const SizedBox(width: AppSpacing.sm),
              TextButton(onPressed: _resend, child: const Text("Renvoyer")),
            ],
          ),
        ],
      ),
    );
  }
}

/// Création (première fois) ou changement (30 jours d'écart) du pseudo.
class _PseudoForm extends ConsumerStatefulWidget {
  const _PseudoForm({required this.first});

  final bool first;

  @override
  ConsumerState<_PseudoForm> createState() => _PseudoFormState();
}

class _PseudoFormState extends ConsumerState<_PseudoForm> {
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
    try {
      await ref.read(communityControllerProvider).setPseudo(_controller.text.trim());
      if (mounted && !widget.first) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e) ?? accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.first ? "Choisis ton pseudo" : "Changer de pseudo", style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.first
              ? "C'est le nom que verront tes amis dans les classements. 3 à 20 caractères, modifiable ensuite une fois par mois."
              : "3 à 20 caractères. Tu ne pourras plus le changer pendant 30 jours.",
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: _controller, maxLength: 20, decoration: const InputDecoration(labelText: "Pseudo"), onSubmitted: (_) => _submit()),
        if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.live)),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Valider"),
        ),
      ],
    );
    return widget.first ? SectionCard(child: content) : Padding(padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md), child: content);
  }
}

class _PseudoHeader extends StatelessWidget {
  const _PseudoHeader({required this.profile});

  final ProfileDto profile;

  @override
  Widget build(BuildContext context) {
    final pseudo = profile.pseudo!;
    return Row(
      children: [
        // Appui sur l'avatar : choix parmi la liste fixe.
        GestureDetector(
          onTap: () => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => const _AvatarPicker()),
          child: Stack(
            children: [
              AvatarCircle(avatarUrl: profile.avatarUrl, pseudo: pseudo, radius: 28),
              const Positioned(right: 0, bottom: 0, child: CircleAvatar(radius: 10, backgroundColor: AppColors.gold, child: Icon(Icons.edit_rounded, size: 12, color: AppColors.background))),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(pseudo, style: Theme.of(context).textTheme.titleLarge)),
        if (profile.pseudoChangeWaitDays == 0)
          IconButton(
            tooltip: "Changer de pseudo",
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const _PseudoForm(first: false)),
          ),
      ],
    );
  }
}

/// Choix de l'avatar : un onglet par jeu du catalogue, les logos de ses équipes dessous.
class _AvatarPicker extends ConsumerWidget {
  const _AvatarPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = catalogGames(ref.watch(catalogProvider).value);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: games.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: games.length,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                    child: Align(alignment: Alignment.centerLeft, child: Text("Choisis ton avatar", style: Theme.of(context).textTheme.titleLarge)),
                  ),
                  TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final game in games) Tab(text: game.name)]),
                  Expanded(child: TabBarView(children: [for (final game in games) _TeamLogos(game: game.slug)])),
                ],
              ),
            ),
    );
  }
}

class _TeamLogos extends ConsumerWidget {
  const _TeamLogos({required this.game});

  final String game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(profileProvider).value?.avatarUrl;
    final teams = ref.watch(gameTeamsProvider(game));
    return switch (teams) {
      AsyncData(:final value) => GridView.count(
        padding: const EdgeInsets.all(AppSpacing.md),
        crossAxisCount: 4,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        children: [
          for (final team in value.where((t) => t.imageUrl != null))
            GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref.read(communityControllerProvider).setAvatar(team.id);
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e) ?? accountErrorMessage(e))));
                }
              },
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: current == team.imageUrl ? AppColors.gold : Colors.transparent, width: 2)),
                child: AvatarCircle(avatarUrl: team.imageUrl, radius: 30),
              ),
            ),
        ],
      ),
      AsyncError() => const Center(child: Text("Impossible de charger les équipes.")),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// Stats de pronostics. Les points révèlent des résultats : avec le sans spoil actif, ils
/// restent masqués jusqu'à un appui (comme les scores).
class StatsCard extends ConsumerStatefulWidget {
  const StatsCard({super.key, required this.stats});

  final PredictionStatsDto stats;

  @override
  ConsumerState<StatsCard> createState() => StatsCardState();
}

class StatsCardState extends ConsumerState<StatsCard> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final hidden = (ref.watch(userSettingProvider).value?.spoilerFree ?? true) && !_revealed;
    final s = widget.stats;
    String v(Object value) => hidden ? "•••" : "$value";
    return GestureDetector(
      onLongPress: hidden ? () => setState(() => _revealed = true) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("PRONOSTICS"),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: _Stat(label: "Points", value: v(s.points))),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(child: _Stat(label: "Justes", value: v("${s.correctCount}/${s.settledCount}"))),
            ],
          ),
          const SizedBox(height: AppSpacing.cardGap),
          Row(
            children: [
              Expanded(child: _Stat(label: "Série en cours", value: v(s.currentStreak))),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(child: _Stat(label: "Meilleure série", value: v(s.bestStreak))),
            ],
          ),
          if (hidden) const Padding(padding: EdgeInsets.only(top: AppSpacing.sm), child: Text("Sans spoil : appui long pour afficher.", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption))),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTextStyles.heroScore),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap});

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

class _AccountActions extends ConsumerWidget {
  const _AccountActions();

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer mon compte ?"),
        content: const Text("Ton compte, tes suivis, tes pronostics et tes groupes seront supprimés définitivement."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Supprimer", style: TextStyle(color: AppColors.live))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(accountServiceProvider).deleteAccount();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e) ?? accountErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.read(accountServiceProvider).email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (email != null) Text("Connecté : $email", style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption)),
        TextButton(onPressed: () => ref.read(accountServiceProvider).signOut(), child: const Text("Se déconnecter")),
        TextButton(onPressed: () => _delete(context, ref), child: const Text("Supprimer mon compte", style: TextStyle(color: AppColors.live))),
      ],
    );
  }
}

/// « Mes tutos » : tutos lus et quiz réussis (J12), avec accès à la liste des tutos de Valorant.
class _LearnRow extends ConsumerWidget {
  const _LearnRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(learnReadProvider).value;
    final read = progress?.read.length ?? 0;
    final passed = progress?.passed.length ?? 0;
    return SectionCard(
      child: _NavRow(
        icon: Icons.school_outlined,
        label: "Mes tutos · $read lus, $passed quiz réussis",
        onTap: () => openLearnGuide(context, "valorant"),
      ),
    );
  }
}
