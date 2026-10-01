import "package:flutter/material.dart";
import "../../theme/tokens.dart";

/// Version des conditions (à garder égale à `FORUM_TERMS_VERSION` de `packages/domain`) : la monter
/// des deux côtés force tout le monde à les accepter de nouveau.
const forumTermsVersion = 1;

/// Conditions d'utilisation du forum (docs/04 J13), écrites pour être lues : courtes, en français.
const _sections = <(String, String)>[
  (
    "De quoi s'agit-il ?",
    "Le forum te permet de discuter d'un match, d'une équipe, d'une compétition ou d'un jeu avec les autres utilisateurs de l'appli. "
        "Il est gratuit, sans publicité, et animé par l'équipe du projet. L'appli est indépendante : elle n'a aucun lien avec les équipes, "
        "les ligues ou les éditeurs de jeux dont elle parle.",
  ),
  (
    "Ton compte et ton pseudo",
    "Il faut un compte avec une adresse e-mail vérifiée et un pseudo pour écrire, et le compte doit avoir au moins 24 heures. "
        "Lire le forum est possible sans compte. Ton pseudo et ton avatar (le logo d'une équipe) sont visibles de tous les lecteurs. "
        "Choisis un pseudo qui ne se fait pas passer pour quelqu'un d'autre ni pour l'équipe du projet.",
  ),
  (
    "Les règles",
    "Sur le forum, on discute. Sont interdits :\n"
        "• les insultes, moqueries ciblées, menaces et le harcèlement, y compris envers un joueur, une équipe ou un autre utilisateur ;\n"
        "• les propos racistes, sexistes, homophobes, discriminatoires ou qui font l'apologie de la haine ou de la violence ;\n"
        "• les contenus sexuels, choquants, ou qui encouragent l'automutilation ;\n"
        "• le spam, la publicité, les messages répétés et les liens (le forum est en texte seul : pas d'image, pas de lien) ;\n"
        "• la publication d'informations personnelles, les tiennes comme celles des autres ;\n"
        "• les contenus illégaux et la diffusion de rumeurs présentées comme des faits sur des personnes réelles ;\n"
        "• les spoilers non annoncés : on ne dévoile pas un résultat dans un fil sans prévenir.\n"
        "Le désaccord est permis, pas le manque de respect.",
  ),
  (
    "Ce que tu écris",
    "Tu es responsable de tes messages. Tu gardes tes droits dessus, mais tu nous autorises à les afficher aux autres utilisateurs, "
        "dans l'appli, tant qu'ils y sont publiés. Tu peux supprimer un de tes messages à tout moment.",
  ),
  (
    "Signaler, bloquer, modérer",
    "Tu peux signaler un message (insulte, spam, spoiler, autre) et bloquer un utilisateur : ses messages disparaissent alors pour toi. "
        "Un message signalé par plusieurs personnes est masqué automatiquement en attendant qu'un modérateur le revoie. "
        "Les modérateurs peuvent retirer un message, verrouiller une discussion et exclure du forum un utilisateur qui ne respecte pas ces règles, "
        "avec ou sans avertissement selon la gravité. Si tu penses qu'une décision est une erreur, tu peux nous contacter par le moyen indiqué "
        "sur la fiche de l'application ; nous la réexaminons.",
  ),
  (
    "Tes données",
    "Nous conservons ton pseudo, ton avatar, le camp que tu choisis, tes messages, tes réactions, tes signalements et tes blocages, "
        "uniquement pour faire fonctionner le forum et le modérer. Ils ne sont ni vendus ni utilisés pour de la publicité. "
        "Quand tu supprimes ton compte, tes messages et tes réactions sont supprimés avec lui ; les réponses écrites par d'autres restent, "
        "sans le message auquel elles répondaient. Tu peux demander l'accès à tes données ou leur suppression à tout moment.",
  ),
  (
    "Contenu illicite",
    "Si tu vois un contenu manifestement illégal, signale-le : nous le retirons dès que possible après l'avoir vu. "
        "Nous pouvons être amenés à transmettre des informations aux autorités si la loi l'exige.",
  ),
  (
    "Responsabilité",
    "Le forum est proposé tel quel, par un projet open source non commercial. Les messages n'engagent que leurs auteurs. "
        "Nous pouvons suspendre ou fermer le forum, ou une discussion, à tout moment.",
  ),
  (
    "Changements",
    "Ces conditions peuvent évoluer. Quand elles changent de façon importante, l'appli te demande de les accepter de nouveau avant d'écrire.",
  ),
];

/// Conditions d'utilisation du forum. Avec [requireAcceptance], un bouton « J'accepte » ferme l'écran
/// en renvoyant `true` (à accepter avant un premier message) ; sinon c'est une simple lecture.
class ForumTermsScreen extends StatelessWidget {
  const ForumTermsScreen({super.key, this.requireAcceptance = false});

  final bool requireAcceptance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Conditions du forum")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            for (final (title, body) in _sections) ...[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(body, style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (requireAcceptance) ...[
              const Text(
                "En continuant, tu confirmes avoir lu ces conditions et tu t'engages à les respecter.",
                style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("J'accepte")),
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Plus tard")),
            ],
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}
