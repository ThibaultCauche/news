import "dart:typed_data";

import "package:dio/dio.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/api_providers.dart";
import "package:mobile/core/auth/auth_store.dart";
import "package:mobile/features/follows/follows_provider.dart";
import "package:news_api_client/news_api_client.dart";
import "package:shared_preferences/shared_preferences.dart";
import "follows_test_helpers.dart";

/// Répond sans jamais toucher au réseau : POST renvoie un `SubscriptionDto`
/// minimal, DELETE un corps vide, avec le code HTTP voulu par le test.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._statusCode);
  final int _statusCode;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = options.method == "POST"
        ? '{"id":"sub-1","targetType":"entity","targetId":"team-a","level":"all","notifyReminder":true,"notifyStart":true,"notifyResult":true,"muted":false}'
        : "";
    return ResponseBody.fromString(
      body,
      _statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Future<ProviderContainer> _makeContainer({required int statusCode, required List<FollowStateDto> initial}) async {
  final dio = Dio()..httpClientAdapter = _FakeAdapter(statusCode);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
        overrideSignedInForTest(),
      overrideFollowsWith(initial),
      apiClientProvider.overrideWithValue(NewsApiClient(dio: dio)),
      authStoreProvider.overrideWithValue(AuthStore(prefs)),
    ],
  );
  addTearDown(container.dispose);
  // `followsProvider` est `autoDispose` : sans un auditeur, le conteneur le
  // détruit dès que ce `read` se termine (comme si aucun écran ne l'observait).
  container.listen(followsProvider, (previous, next) {});
  // Attend le premier `build()` : sans ça, `state` vaut encore `AsyncLoading`
  // et la mise à jour optimiste n'a rien à quoi s'ajouter.
  await container.read(followsProvider.future);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test("follow() met la pastille à jour avant la réponse réseau (J8 : latence perçue)", () async {
    final container = await _makeContainer(statusCode: 201, initial: const []);
    final future = container.read(followsControllerProvider).follow(FollowTargetType.entity, "team-a", name: "G2");

    // Toujours avant l'`await` réseau : le premier tronçon synchrone de
    // `follow()` a déjà posé l'entrée optimiste.
    expect(isFollowing(container.read(followsProvider).value, FollowTargetType.entity, "team-a"), isTrue);

    await future;
  });

  test("unfollow() retire la pastille avant la réponse réseau", () async {
    final existing = FollowStateDto(
      (b) => b
        ..id = "sub-1"
        ..targetType = "entity"
        ..targetId = "team-a"
        ..level = "all"
        ..notifyReminder = true
        ..notifyStart = true
        ..notifyResult = true
        ..muted = false
        ..name = "G2",
    );
    final container = await _makeContainer(statusCode: 200, initial: [existing]);
    final future = container.read(followsControllerProvider).unfollow(FollowTargetType.entity, "team-a");

    expect(isFollowing(container.read(followsProvider).value, FollowTargetType.entity, "team-a"), isFalse);
    await future;
  });

  test("follow() annule la mise à jour optimiste si le serveur refuse", () async {
    final container = await _makeContainer(statusCode: 500, initial: const []);
    final controller = container.read(followsControllerProvider);

    await expectLater(
      controller.follow(FollowTargetType.entity, "team-a", name: "G2"),
      throwsA(isA<DioException>()),
    );
    expect(isFollowing(container.read(followsProvider).value, FollowTargetType.entity, "team-a"), isFalse);
  });
}
