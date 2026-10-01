import "package:dio/dio.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/auth/account.dart";

DioException _dio(int? status, [Object? data]) {
  final options = RequestOptions(path: "/x");
  return DioException(
    requestOptions: options,
    type: status == null ? DioExceptionType.connectionError : DioExceptionType.badResponse,
    response: status == null ? null : Response(requestOptions: options, statusCode: status, data: data),
  );
}

void main() {
  // Aucun message affiché ne doit contenir de code, de mot anglais courant ni de texte d'exception.
  final technical = RegExp(r"\d{3}|Exception|Unauthorized|Forbidden|Internal|Too Many|error|firebase|auth/", caseSensitive: false);

  test("erreurs Firebase connues ou inconnues : texte français sans code", () {
    for (final code in ["invalid-credential", "email-already-in-use", "requires-recent-login", "operation-not-allowed", "quota-exceeded"]) {
      final message = accountErrorMessage(FirebaseAuthException(code: code));
      expect(message, isNot(contains(code)));
      expect(technical.hasMatch(message), isFalse, reason: message);
    }
  });

  test("erreurs réseau et serveur : texte français sans code HTTP", () {
    for (final status in [null, 400, 401, 403, 404, 429, 500, 502, 503]) {
      final message = accountErrorMessage(_dio(status, {"message": "Internal server error", "statusCode": status}));
      expect(technical.hasMatch(message), isFalse, reason: "$status : $message");
    }
  });

  test("le texte d'une refus métier (400, 403, 404, 409) est repris, pas celui d'une erreur générique", () {
    expect(apiErrorMessage(_dio(409, {"code": "PSEUDO_TAKEN", "message": "Ce pseudo est déjà pris"})), "Ce pseudo est déjà pris");
    expect(apiErrorMessage(_dio(404, {"message": "Code de groupe inconnu"})), "Code de groupe inconnu");
    expect(apiErrorMessage(_dio(429, {"message": "ThrottlerException: Too Many Requests"})), isNull);
    expect(apiErrorMessage(_dio(401, {"message": "Unauthorized"})), isNull);
    expect(apiErrorMessage(_dio(500, {"message": "Internal server error"})), isNull);
    // Erreur de validation : `message` est une liste, pas un texte à montrer.
    expect(apiErrorMessage(_dio(400, {"message": ["pseudo must be a string"]})), isNull);
  });

  test("n'importe quelle autre exception : message générique", () {
    expect(technical.hasMatch(accountErrorMessage(StateError("boom"))), isFalse);
  });
}
