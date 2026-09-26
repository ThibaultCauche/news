import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:shared_preferences/shared_preferences.dart";
import "app.dart";
import "core/api_providers.dart";
import "core/auth/auth_bootstrap.dart";
import "core/auth/auth_store.dart";
import "core/notifications/notification_tap_handler.dart";
import "theme/app_theme.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting("fr_FR");
  final prefs = await SharedPreferences.getInstance();
  final authStore = AuthStore(prefs);
  try {
    await ensureAnonymousAccount(authStore, resolveApiBaseUrl());
  } catch (_) {
    // Hors ligne au tout premier lancement (docs/03 §11) : l'appli reste
    // utilisable en lecture (`/v1/home` fonctionne sans compte), un prochain
    // lancement recréera le compte.
  }
  // Démarrage "à froid" depuis une notification : le `Navigator` n'existe pas
  // encore, on programme la navigation pour juste après le premier affichage.
  final initialMatchId = await setupNotificationTapHandling();
  runApp(ProviderScope(overrides: [authStoreProvider.overrideWithValue(authStore)], child: const NewsRoot()));
  if (initialMatchId != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => openMatch(initialMatchId));
  }
}

class NewsRoot extends StatelessWidget {
  const NewsRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: "News",
      debugShowCheckedModeBanner: false,
      locale: const Locale("fr"),
      supportedLocales: const [Locale("fr")],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAppTheme(),
      home: const NewsApp(),
    );
  }
}
