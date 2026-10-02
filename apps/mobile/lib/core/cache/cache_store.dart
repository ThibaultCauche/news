import "package:drift/drift.dart";
import "app_database.dart";

class CachedEntry {
  const CachedEntry({required this.body, required this.etag, required this.storedAt});

  final String body;
  final String? etag;
  final DateTime storedAt;
}

/// Façade au-dessus de `AppDatabase` : le reste de l'appli manipule des
/// [CachedEntry], pas des lignes drift.
class CacheStore {
  CacheStore(this._db);

  final AppDatabase _db;

  Future<CachedEntry?> read(String key) async {
    final row = await (_db.select(
      _db.cachedResponses,
    )..where((t) => t.requestKey.equals(key))).getSingleOrNull();
    if (row == null) return null;
    return CachedEntry(body: row.body, etag: row.etag, storedAt: row.storedAt);
  }

  Future<void> write(String key, {required String body, String? etag}) {
    return _db
        .into(_db.cachedResponses)
        .insertOnConflictUpdate(
          CachedResponsesCompanion.insert(
            requestKey: key,
            body: body,
            etag: Value(etag),
            storedAt: DateTime.now(),
          ),
        );
  }

  /// Déconnexion : les réponses en cache (accueil personnalisé…) appartenaient au compte quitté.
  Future<void> clear() => _db.delete(_db.cachedResponses).go();
}
