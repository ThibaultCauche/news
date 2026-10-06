import "dart:convert";
import "dart:math" as math;
import "dart:ui" as ui;
import "package:dio/dio.dart";
import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:shared_preferences/shared_preferences.dart";
import "../../theme/tokens.dart";

/// Notifications push affichées par l'appli elle-même (J22, #M11) : le serveur envoie un message
/// « data » (titre, texte, `tag`, `imageUrl`, `eventId`…) et l'appli en fait une notification avec le
/// logo de l'équipe en **petite icône** (FCM ne sait afficher qu'une grande image, trop envahissante).
/// Le `tag` d'un match remplace sa notification précédente (rappel → début → résultat).
/// Android uniquement : iOS est reporté après la sortie de l'appli.
final _plugin = FlutterLocalNotificationsPlugin();

const _channelId = "keryx_alerts";
const _channelName = "Alertes Keryx";
const _groupKey = "keryx_matches";
const _summaryId = 1;

/// Choix de l'utilisateur (Réglages) : logo de l'équipe en petite icône, ou notification sans icône.
const teamLogoPrefKey = "notif.teamLogo";

/// Lu à chaque notification, et rechargé : l'isolat des messages en arrière-plan peut garder un ancien cache.
Future<bool> teamLogoInNotifications() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(teamLogoPrefKey) ?? true;
  } catch (_) {
    return true;
  }
}

AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

/// Les notifications sont-elles autorisées pour l'appli (permission Android et réglage du système) ?
/// Vrai en cas de doute (plateforme sans notifications, tests) : on n'alarme pas à tort.
Future<bool> areNotificationsEnabled() async {
  try {
    return await _android?.areNotificationsEnabled() ?? true;
  } catch (_) {
    return true;
  }
}

/// Redemande la permission (Android 13+). Sans effet si l'utilisateur l'a déjà refusée deux fois : il doit
/// alors l'activer dans les réglages du téléphone.
Future<bool> requestNotificationPermission() async {
  try {
    return await _android?.requestNotificationsPermission() ?? true;
  } catch (_) {
    return true;
  }
}

/// À appeler une fois (dans l'isolat principal comme dans celui des messages en arrière-plan).
/// [onTap] reçoit les données du message quand on ouvre la notification.
Future<void> initLocalNotifications({void Function(Map<String, dynamic> data)? onTap}) async {
  await _plugin.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings("ic_stat_keryx")),
    onDidReceiveNotificationResponse: (response) {
      final data = _decode(response.payload);
      if (data != null) onTap?.call(data);
    },
  );
}

/// Données de la notification qui a lancé l'appli à froid, s'il y en a une.
Future<Map<String, dynamic>?> launchNotificationData() async {
  final details = await _plugin.getNotificationAppLaunchDetails();
  if (details?.didNotificationLaunchApp != true) return null;
  return _decode(details!.notificationResponse?.payload);
}

Map<String, dynamic>? _decode(String? payload) {
  if (payload == null) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(payload) as Map);
  } catch (_) {
    return null;
  }
}

/// Affiche la notification d'un message « data ». Sans logo (ou s'il ne se télécharge pas vite), la
/// notification part quand même, simplement sans icône d'équipe.
Future<void> showPushNotification(Map<String, dynamic> data) async {
  final title = data["title"] as String?;
  final body = data["body"] as String?;
  if (title == null && body == null) return;
  final tag = data["tag"] as String?;
  final imageUrl = data["imageUrl"] as String?;
  final raw = imageUrl == null || !await teamLogoInNotifications() ? null : await _downloadLogo(imageUrl);
  final logo = raw == null ? null : await _logoTile(raw);
  await _plugin.show(
    id: (tag ?? "${data["eventId"] ?? data["threadId"] ?? title}").hashCode & 0x7fffffff,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
        tag: tag,
        groupKey: _groupKey,
        color: AppColors.brass,
        largeIcon: logo == null ? null : ByteArrayAndroidBitmap(logo),
      ),
    ),
    payload: jsonEncode(data),
  );
  await _updateSummary();
}

/// À partir de deux alertes affichées, Android les range sous une seule : « 3 alertes », dépliable.
/// Le résumé disparaît tout seul quand il ne reste plus d'alerte en dessous.
Future<void> _updateSummary() async {
  try {
    final active = (await _plugin.getActiveNotifications()).where((n) => n.id != _summaryId && n.channelId == _channelId).toList();
    if (active.length < 2) {
      await _plugin.cancel(id: _summaryId);
      return;
    }
    await _plugin.show(
      id: _summaryId,
      title: "Keryx",
      body: "${active.length} alertes",
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          groupKey: _groupKey,
          setAsGroupSummary: true,
          groupAlertBehavior: GroupAlertBehavior.children,
          color: AppColors.brass,
          styleInformation: InboxStyleInformation([for (final n in active) [?n.title, ?n.body].join(" : ")], summaryText: "${active.length} alertes"),
        ),
      ),
    );
  } catch (_) {
    // Le résumé n'est qu'un confort : sans lui, les alertes restent affichées une par une.
  }
}

/// Logo posé dans une tuile carrée à coins arrondis : sans ça, Android rogne un logo large (NRG) au centre. Tuile
/// claire pour un logo plutôt sombre (noir sur noir, illisible), sombre sinon. Renvoie `null` si l'image ne se décode pas
/// (la notification part alors sans icône).
Future<Uint8List?> _logoTile(Uint8List logo) async {
  try {
    const size = 192.0;
    final codec = await ui.instantiateImageCodec(logo, targetWidth: 160);
    final image = (await codec.getNextFrame()).image;
    final pixels = (await image.toByteData())!.buffer.asUint8List();
    var luminance = 0.0;
    var opaque = 0;
    for (var i = 0; i + 3 < pixels.length; i += 4) {
      if (pixels[i + 3] < 128) continue;
      luminance += 0.2126 * pixels[i] + 0.7152 * pixels[i + 1] + 0.0722 * pixels[i + 2];
      opaque++;
    }
    final dark = opaque > 0 && luminance / opaque / 255 < 0.3;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, size, size));
    canvas.drawRRect(ui.RRect.fromRectAndRadius(const ui.Rect.fromLTWH(0, 0, size, size), const ui.Radius.circular(40)), ui.Paint()..color = dark ? const ui.Color(0xFFECECEC) : const ui.Color(0xFF1C1C21));
    const box = size * 0.7;
    final scale = math.min(box / image.width, box / image.height);
    final target = ui.Rect.fromCenter(center: const ui.Offset(size / 2, size / 2), width: image.width * scale, height: image.height * scale);
    canvas.drawImageRect(image, ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), target, ui.Paint()..filterQuality = ui.FilterQuality.high);
    final tile = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final png = await tile.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  } catch (_) {
    // Pas de tuile : la notification part sans icône d'équipe.
    return null;
  }
}

Future<Uint8List?> _downloadLogo(String url) async {
  try {
    final response = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 4), sendTimeout: const Duration(seconds: 4)),
    );
    final bytes = response.data;
    return bytes == null ? null : Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  }
}

/// Messages reçus pendant que l'appli est en arrière-plan ou fermée : isolat à part, d'où le point
/// d'entrée explicite et la ré-initialisation de Firebase.
@pragma("vm:entry-point")
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await initLocalNotifications();
  await showPushNotification(message.data);
}
