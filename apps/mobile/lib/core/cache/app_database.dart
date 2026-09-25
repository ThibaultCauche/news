import "package:drift/drift.dart";
import "package:drift_flutter/drift_flutter.dart";

part "app_database.g.dart";

/// Cache générique clé/valeur : une ligne par requête `GET` (chemin + query),
/// avec l'`ETag` renvoyé par l'API et le corps JSON brut. Sert à la fois à
/// éviter de re-télécharger une réponse inchangée (`If-None-Match`) et à
/// afficher la dernière réponse connue immédiatement, avant même le réseau
/// (docs/03 §11 : "hors ligne d'abord").
class CachedResponses extends Table {
  TextColumn get requestKey => text()();
  TextColumn get etag => text().nullable()();
  TextColumn get body => text()();
  DateTimeColumn get storedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {requestKey};
}

@DriftDatabase(tables: [CachedResponses])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 1;
}

QueryExecutor _openConnection() {
  return driftDatabase(name: "news_cache");
}
