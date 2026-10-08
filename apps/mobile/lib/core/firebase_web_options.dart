import "package:firebase_core/firebase_core.dart";
import "package:flutter/foundation.dart" show kIsWeb;

/// Options Firebase du web (non secrètes), passées au build :
/// `--dart-define=FIREBASE_WEB_API_KEY=… --dart-define=FIREBASE_WEB_APP_ID=… --dart-define=FIREBASE_WEB_SENDER_ID=…
/// --dart-define=FIREBASE_WEB_PROJECT_ID=… --dart-define=FIREBASE_WEB_AUTH_DOMAIN=…` (console Firebase, appli Web).
/// Sur mobile, `null` : le plugin lit `google-services.json`.
FirebaseOptions? get firebaseOptionsForPlatform => kIsWeb
    ? const FirebaseOptions(
        apiKey: String.fromEnvironment("FIREBASE_WEB_API_KEY"),
        appId: String.fromEnvironment("FIREBASE_WEB_APP_ID"),
        messagingSenderId: String.fromEnvironment("FIREBASE_WEB_SENDER_ID"),
        projectId: String.fromEnvironment("FIREBASE_WEB_PROJECT_ID"),
        authDomain: String.fromEnvironment("FIREBASE_WEB_AUTH_DOMAIN"),
      )
    : null;
