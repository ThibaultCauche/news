/// Le client généré représente les dates de l'API en `String` (ISO 8601) :
/// ce fichier centralise le seul `DateTime.parse` de l'appli.
extension NullableIsoDate on String? {
  DateTime? get toDateTime => this == null ? null : DateTime.parse(this!);
}

extension IsoDate on String {
  DateTime get toDateTime => DateTime.parse(this);
}
