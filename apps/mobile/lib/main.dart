import "package:dio/dio.dart" show DioException;
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_core/firebase_core.dart";
import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:sentry_flutter/sentry_flutter.dart";
import "package:shared_preferences/shared_preferences.dart";
import "app.dart";
import "core/api_providers.dart";
import "core/auth/auth_store.dart";
import "core/navigation.dart";
import "core/notifications/notification_tap_handler.dart";
import "features/onboarding/onboarding_flow.dart";
import "theme/app_theme.dart";

/// Riverpod 3 relance par défaut un provider en échec jusqu'à 10 fois (attente doublée à chaque fois,
/// ~40 s au total) en le laissant « en chargement » : l'écran restait en skeleton 40 s avant d'afficher
/// l'erreur (trouvé au J18 par le test d'intégration). Un seul nouvel essai après 1 s, puis l'erreur.
Duration? appProviderRetry(int retryCount, Object error) => retryCount < 1 ? const Duration(seconds: 1) : null;

// Compte rendu des erreurs inattendues (J18) : seulement si un DSN est fourni au build
// (`--dart-define=SENTRY_DSN=...`), jamais en debug sans DSN. Pas de données personnelles envoyées.
const _sentryDsn = String.fromEnvironment("SENTRY_DSN");

Future<void> main() async {
  if (_sentryDsn.isEmpty) return _start();
  await SentryFlutter.init((options) {
    options.dsn = _sentryDsn;
    options.sendDefaultPii = false;
    options.tracesSampleRate = 0;
    options.environment = const bool.fromEnvironment("dart.vm.product") ? "release" : "debug";
    // Réseau coupé, 4xx, jeton expiré : cas prévus et déjà gérés à l'écran, pas des bugs.
    options.beforeSend = (event, hint) => event.throwable is DioException ? null : event;
  }, appRunner: _start);
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting("fr_FR");
  final prefs = await SharedPreferences.getInstance();
  final authStore = AuthStore(prefs);
  try {
    await Firebase.initializeApp();
    // E-mails de vérification et de réinitialisation en français.
    await FirebaseAuth.instance.setLanguageCode("fr");
  } catch (_) {
    // Projet Firebase pas relié côté appli (`google-services.json` absent) : la navigation
    // reste possible, seule la connexion échouera (message affiché à l'écran de connexion).
  }
  // Démarrage "à froid" depuis une notification : le `Navigator` n'existe pas
  // encore, on programme la navigation pour juste après le premier affichage.
  final initialTarget = await setupNotificationTapHandling();
  runApp(ProviderScope(retry: appProviderRetry, overrides: [authStoreProvider.overrideWithValue(authStore)], child: const NewsRoot()));
  if (initialTarget != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => openFromNotification(initialTarget));
  }
}

class NewsRoot extends StatelessWidget {
  const NewsRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: "Keryx",
      debugShowCheckedModeBanner: false,
      locale: const Locale("fr"),
      supportedLocales: const [Locale("fr")],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAppTheme(),
      // La mise en page est pensée pour l'échelle mesurée des maquettes
      // (docs/maquettes/specs/commun.md) : on suit les réglages d'accessibilité
      // du lecteur sans casser les cartes en dessous de la taille système, ni
      // au-delà de 1,2x (docs/02 — passe fidélité visuelle, étape 2).
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: mediaQuery.textScaler.clamp(minScaleFactor: 1, maxScaleFactor: 1.2)),
          child: child!,
        );
      },
      home: const _AppRoot(),
    );
  }
}

/// Onboarding (écrans 11-12, J6) montré une fois au premier lancement, avant
/// la tab bar principale — "Passer" a le même effet que d'aller au bout.
class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot();

  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot> {
  late bool _onboardingDone = ref.read(authStoreProvider).hasSeenOnboarding;

  void _finishOnboarding() {
    ref.read(authStoreProvider).markOnboardingSeen();
    setState(() => _onboardingDone = true);
  }

  @override
  Widget build(BuildContext context) {
    return _onboardingDone ? const NewsApp() : OnboardingFlow(onDone: _finishOnboarding);
  }
}
