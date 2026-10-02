import "package:dio/dio.dart";

const _startKey = "traceStart";

/// Journal « HTTP GET /v1/home 200 412 ms » pour mesurer la lenteur ressentie sur un vrai téléphone (J19).
/// Actif seulement avec `--dart-define=HTTP_TRACE=true` ; rien n'est journalisé de la requête hors méthode, chemin et statut.
class HttpTraceInterceptor extends Interceptor {
  void _log(RequestOptions options, String status) {
    final start = options.extra[_startKey] as int?;
    final ms = start == null ? -1 : DateTime.now().millisecondsSinceEpoch - start;
    // `debugPrint` ne sort rien en release : `print` arrive dans `adb logcat -s flutter`.
    // ignore: avoid_print
    print("HTTP ${options.method} ${options.uri.path} $status $ms ms");
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, "${response.statusCode}");
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, "${err.response?.statusCode ?? err.type.name}");
    handler.next(err);
  }
}
