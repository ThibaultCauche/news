import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/material.dart";
import "../../features/forum/thread_screen.dart";
import "../../features/next_match/next_match_screen.dart";
import "local_notifications.dart";

/// Clé du `Navigator` racine : accessible en dehors de l'arbre de widgets,
/// pour naviguer depuis un tap sur une notification (docs/04 J4).
final navigatorKey = GlobalKey<NavigatorState>();

/// Données d'une notification ouverte : `eventId` (match) ou `threadId` (réponse du forum).
typedef NotificationTarget = Map<String, dynamic>;

/// Configure Firebase (si possible) et écoute les taps sur une notification
/// reçue pendant que l'appli tourne. Renvoie l'id du match concerné si
/// l'appli a été ouverte *depuis* une notification (démarrage à froid) —
/// à traiter après le premier affichage, le `Navigator` n'existe pas encore
/// à cet instant. Échoue sans bruit tant que Firebase n'est pas configuré.
Future<NotificationTarget?> setupNotificationTapHandling() async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    return null;
  }
  // Les notifications sont affichées par l'appli (message « data », `local_notifications.dart`) : le tap
  // vient du plugin. Les écouteurs FCM restent pour d'éventuelles notifications envoyées par la console.
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  await initLocalNotifications(onTap: openFromNotification);
  FirebaseMessaging.onMessageOpenedApp.listen((message) => openFromNotification(message.data));
  final launchData = await launchNotificationData();
  if (launchData != null) return launchData;
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  return initialMessage?.data;
}

void openFromNotification(NotificationTarget data) {
  final threadId = data["threadId"];
  if (threadId is String) {
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ForumThreadScreen(threadId: threadId)));
  } else if (data["eventId"] is String) {
    openMatch(data["eventId"] as String);
  }
}

void openMatch(String eventId) {
  navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: eventId)));
}
