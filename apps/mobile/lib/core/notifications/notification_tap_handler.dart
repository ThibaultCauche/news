import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/material.dart";
import "../../features/next_match/next_match_screen.dart";

/// Clé du `Navigator` racine : accessible en dehors de l'arbre de widgets,
/// pour naviguer depuis un tap sur une notification (docs/04 J4).
final navigatorKey = GlobalKey<NavigatorState>();

/// Configure Firebase (si possible) et écoute les taps sur une notification
/// reçue pendant que l'appli tourne. Renvoie l'id du match concerné si
/// l'appli a été ouverte *depuis* une notification (démarrage à froid) —
/// à traiter après le premier affichage, le `Navigator` n'existe pas encore
/// à cet instant. Échoue sans bruit tant que Firebase n'est pas configuré.
Future<String?> setupNotificationTapHandling() async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    return null;
  }
  FirebaseMessaging.onMessageOpenedApp.listen(_openMatchFromMessage);
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  return initialMessage?.data["eventId"];
}

void _openMatchFromMessage(RemoteMessage message) {
  final eventId = message.data["eventId"];
  if (eventId != null) openMatch(eventId);
}

void openMatch(String eventId) {
  navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: eventId)));
}
