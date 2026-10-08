import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:package_info_plus/package_info_plus.dart";
import "api_providers.dart";

/// Lien de l'appli sur le Play Store (J21) ; la bêta fermée s'ouvre par le même lien une fois publiée.
final storeUri = Uri.https("play.google.com", "/store/apps/details", {"id": "com.news.mobile"});

/// Compare deux versions « 1.2.3 » (un suffixe « +build » ou « -beta » est ignoré) : négatif si [a] < [b].
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split(RegExp("[+-]")).first.split(".")) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

enum UpdateLevel { none, suggested, required }

class AppUpdate {
  const AppUpdate(this.level, {this.notes, this.message, this.version});
  final UpdateLevel level;
  final String? notes;

  /// Message de service (J17) : bandeau fermable, quelle que soit la version.
  final String? message;

  /// Version installée, pour la feuille « Quoi de neuf » (une seule fois par version).
  final String? version;
}

/// La version installée ; remplacée dans les tests (le plugin n'existe pas sous `flutter test`).
final installedVersionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

/// Au lancement : la version est-elle sous `latest` (bandeau) ou sous `minSupported` (écran bloquant) ?
/// Un échec (hors ligne, API coupée) ne bloque jamais : on ne dit rien.
final appUpdateProvider = FutureProvider<AppUpdate>((ref) async {
  try {
    final installed = await ref.watch(installedVersionProvider.future);
    final res = await ref.watch(apiClientProvider).getAppVersionApi().appVersionControllerGet();
    final v = res.data!;
    AppUpdate at(UpdateLevel level) => AppUpdate(level, notes: v.notes, message: v.message, version: installed);
    if (compareVersions(installed, v.minSupported) < 0) return at(UpdateLevel.required);
    if (compareVersions(installed, v.latest) < 0) return at(UpdateLevel.suggested);
    return at(UpdateLevel.none);
  } catch (_) {}
  return const AppUpdate(UpdateLevel.none);
});
