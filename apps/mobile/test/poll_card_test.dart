import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/discussion/shared_cards.dart";
import "package:mobile/features/forum/forum_providers.dart";
import "package:news_api_client/news_api_client.dart";

class _FakeForumController extends ForumController {
  _FakeForumController(super.ref, this.calls);

  final List<int?> calls;

  @override
  Future<void> vote(String threadId, String messageId, int? option) async => calls.add(option);
}

ForumPollDto _poll({int? myVote, bool closed = false}) => ForumPollDto(
  (b) => b
    ..total = 3
    ..closed = closed
    ..endsAt = closed ? DateTime.now().subtract(const Duration(hours: 1)) : null
    ..myVote = myVote
    ..options.replace([
      ForumPollOptionDto((o) => o..label = "Alpha"..votes = 2),
      ForumPollOptionDto((o) => o..label = "Beta"..votes = 1),
    ]),
);

Widget _app(List<int?> calls, ForumPollDto poll) => ProviderScope(
  key: UniqueKey(),
  overrides: [forumControllerProvider.overrideWith((ref) => _FakeForumController(ref, calls))],
  child: MaterialApp(home: Scaffold(body: PollCard(threadId: "t", messageId: "m", question: "Qui gagne ?", poll: poll))),
);

void main() {
  testWidgets("affiche la question, les options et le total", (tester) async {
    await tester.pumpWidget(_app([], _poll()));
    expect(find.text("Qui gagne ?"), findsOneWidget);
    expect(find.text("Alpha"), findsOneWidget);
    expect(find.text("3 votes"), findsOneWidget);
  });

  testWidgets("un tap vote, et re-toucher son choix le retire", (tester) async {
    final calls = <int?>[];
    await tester.pumpWidget(_app(calls, _poll()));
    await tester.tap(find.text("Beta"));
    await tester.pumpAndSettle();
    expect(calls, [1]);

    final again = <int?>[];
    await tester.pumpWidget(_app(again, _poll(myVote: 1)));
    await tester.tap(find.text("Beta"));
    await tester.pumpAndSettle();
    expect(again, [null]);
  });

  testWidgets("un sondage terminé ne se vote plus et le dit", (tester) async {
    final calls = <int?>[];
    await tester.pumpWidget(_app(calls, _poll(closed: true)));
    expect(find.textContaining("Sondage terminé"), findsOneWidget);
    await tester.tap(find.text("Beta"));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });
}
