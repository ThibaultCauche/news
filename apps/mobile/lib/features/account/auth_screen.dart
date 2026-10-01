import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/auth/account.dart";
import "../../theme/tokens.dart";
import "../../widgets/page_title.dart";

/// Création de compte ou connexion (e-mail + mot de passe, Firebase Auth — docs/04 J11).
/// Se ferme avec `true` quand le compte est connecté, pour que l'action qui l'a demandé continue.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.signUp = true});

  final bool signUp;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  late bool _signUp = widget.signUp;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = "Renseigne ton e-mail et ton mot de passe.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final account = ref.read(accountServiceProvider);
    try {
      if (_signUp) {
        await account.signUp(email, password);
      } else {
        await account.signIn(email, password);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = "Saisis d'abord ton e-mail.");
      return;
    }
    try {
      await ref.read(accountServiceProvider).sendPasswordReset(email);
      if (mounted) setState(() => _info = "Si un compte existe pour $email, un e-mail de réinitialisation vient de partir.");
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      // Le bouton principal est ancré en bas, à la même place en connexion et en inscription ; il est dans
      // le corps (et non en `bottomNavigationBar`) pour rester au-dessus du clavier (J15).
      body: Column(
        children: [
          Expanded(
            child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          PageTitle(_signUp ? "Créer un compte" : "Se connecter"),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _signUp
                ? "Un compte te permet de suivre des équipes, recevoir des alertes, pronostiquer et jouer avec tes amis. Tu peux toujours naviguer sans."
                : "Retrouve tes suivis, tes alertes et tes pronostics.",
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: "E-mail"),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
            decoration: InputDecoration(
              labelText: "Mot de passe",
              helperText: _signUp ? "6 caractères minimum" : null,
              suffixIcon: IconButton(
                tooltip: _showPassword ? "Masquer le mot de passe" : "Afficher le mot de passe",
                icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: const TextStyle(color: AppColors.live)),
          ],
          if (_info != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_info!, style: const TextStyle(color: AppColors.textSecondary)),
          ],
          if (!_signUp) Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _busy ? null : _forgotPassword, child: const Text("Mot de passe oublié"))),
        ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_signUp ? "Créer mon compte" : "Me connecter"),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() {
                      _signUp = !_signUp;
                      _error = null;
                      _info = null;
                    }),
                    child: Text(_signUp ? "J'ai déjà un compte" : "Pas encore de compte ? Créer un compte"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
