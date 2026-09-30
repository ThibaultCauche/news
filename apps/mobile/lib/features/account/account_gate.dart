import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/auth/account.dart";
import "../../core/notifications/notification_tap_handler.dart";
import "../../theme/tokens.dart";
import "auth_screen.dart";

/// Garde des actions réservées aux comptes (docs/04 J11) : l'invité qui suit, alerte, met un
/// favori, règle l'appli ou pronostique voit « Crée un compte pour continuer ». Renvoie `true`
/// si l'action peut continuer (déjà connecté, ou connexion réussie dans la foulée). Passe par
/// `navigatorKey` pour fonctionner depuis n'importe quel contrôleur, sans `BuildContext`.
Future<bool> ensureAccount(Ref ref) async {
  if (ref.read(signedInProvider)) return true;
  final context = navigatorKey.currentContext;
  if (context == null) return false;
  final wantsSignUp = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _AccountRequiredSheet(),
  );
  if (wantsSignUp == null || !context.mounted) return false;
  final connected = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AuthScreen(signUp: wantsSignUp)));
  return connected ?? false;
}

class _AccountRequiredSheet extends StatelessWidget {
  const _AccountRequiredSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Crée un compte pour continuer", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              "Naviguer reste libre. Un compte sert à suivre, être alerté, pronostiquer et retrouver tout ça sur un autre téléphone.",
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Créer un compte"))),
            SizedBox(width: double.infinity, child: TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("J'ai déjà un compte"))),
          ],
        ),
      ),
    );
  }
}
