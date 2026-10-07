import "dart:convert";
import "package:flutter_test/flutter_test.dart";
import "package:news_api_client/news_api_client.dart";

// Un message « tableau » (pick'em) doit se lire avec le client généré : si le type manque dans l'enum des messages,
// la page entière du fil échoue (« Impossible de charger la discussion »).
void main() {
  test("une page avec un tableau partagé se désérialise", () {
    const message = '{"id":"m1","threadId":"t1","parentId":null,"author":{"userId":"u1","pseudo":"Tel","avatarUrl":null,"camp":null},"body":"","hidden":false,"replyTo":null,"edited":false,"isSpoiler":false,"kind":"pickem","shared":{"kind":"pickem","refId":"c1","pickedEntityId":null,"pickedScore":null,"otherScore":null,"locked":true,"pickemPicked":14,"pickemTotal":14,"pickemPoints":null},"poll":null,"ideaStatus":null,"pinned":false,"createdAt":"2026-10-07T17:01:32.266Z","reactions":[],"myReaction":null,"replies":[]}';
    final json = jsonDecode(message);
    final dto = standardSerializers.deserializeWith(ForumMessageDto.serializer, json);
    expect(dto, isNotNull);
    expect(dto!.kind, ForumMessageDtoKindEnum.pickem);
    expect(dto.shared!.pickemPicked, 14);
  });
}
